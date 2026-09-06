# 構成の詳細

![構成図](images/architecture.png)

ハンズオンで何をやってもらうかは [curriculum.md](curriculum.md) にあります。

## 全体像

受講者はブラウザで `user01.handson.example.com` のような自分専用の URL を開きます。リクエストは Internet Gateway から Application Load Balancer に入り、ALB が HTTPS を終端したうえで、ホスト名を見て受講者ごとの EC2 に転送します。EC2 の上では code-server が待ち受けていて、パスワードを入力するとブラウザ上に VS Code の画面が出ます。

受講者はその VS Code で Strands Agent の雛形を編集し、ターミナルから `agentcore deploy` を実行します。コードは ZIP にまとめられて S3 に置かれ、AgentCore Runtime がそれを読み取ってマネージドな microVM 上でエージェントを起動します。デプロイが終わったら、ハンズオン UI からエージェントを呼び出します。前半のローカル実行と同じ画面なので、受講者から見た絵は変わらず、実行されている場所だけが変わります。エージェントの内部では Amazon Bedrock の基盤モデルが呼ばれます。

### Runtime からのストリーミング

`InvokeAgentRuntime` は `text/event-stream` を返すので、エージェントの動きをそのまま画面に流せます。ただし Strands のイベントを加工せずに返すことはできません。イベントには Agent オブジェクトそのものが含まれていて、JSON にできず Python の文字列表現のまま届いてしまいます。

そこで画面に出すぶんだけに絞る変換を挟み、その変換をローカル実行と Runtime 実行の両方で共有しています。どちらで動かしても画面に届くイベントの形が同じになるため、実行場所が変わっても表示は変わりません。

## コンポーネント

### ネットワーク

VPC にパブリックサブネットを 2 つの AZ に用意します。ALB は 2 AZ 以上のサブネットを要求するため、AZ は 2 つ必要です。

EC2 もパブリックサブネットに置き、パブリック IP を付けます。インターネットへの下り通信（パッケージの取得、AWS API の呼び出し）が Internet Gateway 経由で通るため、NAT Gateway が要りません。NAT Gateway は起動している間ずっと課金されるので、数時間で捨てる環境では避けたいリソースです。

EC2 のセキュリティグループは、ALB のセキュリティグループからの 8080 番だけを許可します。SSH は開けません。インターネットから EC2 に直接届く経路はありません。

### 入口（ALB と証明書）

ALB は HTTPS:443 のリスナーを持ち、ACM で発行したワイルドカード証明書（`*.handson.example.com`）で TLS を終端します。証明書は 1 枚で受講者全員ぶんのサブドメインをまかなえます。HTTP:80 で来たリクエストは 443 にリダイレクトします。

リスナールールはホストベースで、`user01.handson.example.com` を受講者 01 のターゲットグループに、`user02...` を 02 に、という形で振り分けます。受講者を増やしてもルールとターゲットグループが増えるだけで、ALB は 1 つのままです。

DNS は Cloudflare で管理します。`*.handson.example.com` の CNAME を ALB の DNS 名に向けるレコードを 1 本引けば、サブドメインが何個あっても解決します。このレコードは Terraform が Cloudflare のプロバイダー経由で作るので、ALB を作り直して DNS 名が変わっても手で差し替える必要はありません。Cloudflare のプロキシ（オレンジクラウド）はワイルドカードでは有料プランが必要になるため、DNS only（グレークラウド）で運用します。TLS は ALB 上の ACM 証明書がそのまま使われます。

ACM の証明書検証も DNS 検証なので、Cloudflare に検証用の CNAME を 1 本追加します。

### 受講者の作業環境（EC2）

- インスタンスタイプ: t4g.small（ARM64 / AWS Graviton、2 vCPU / 2GB）。t4g.medium と比べて `agentcore deploy` の所要時間に差が無かった（Issue #15）
- OS: Amazon Linux 2023
- 1 人 1 台

ARM64 を選んでいるのは、AgentCore Runtime が ARM64 でしか動かないためです。ローカルでの動作確認とデプロイ先のアーキテクチャを揃えておくと、受講者が踏むトラブルが減ります。

EC2 には次のものを入れておきます。

- code-server（8080 番。ブラウザ上の VS Code）
- ハンズオン UI（3000 番。code-server の `/proxy/3000/` 経由で開く）。エージェントの動きを可視化する画面で、受講者はトレースをここだけで見る
- Strands Agent の雛形プロジェクト
- AgentCore CLI（`@aws/agentcore`）、AWS CDK、AWS CLI、uv、Node.js、Python

ハンズオン UI を ALB のルールで別に公開せず、code-server が持つポート転送機能（`/proxy/<ポート番号>/`）を通す形にしています。ALB のリスナールールを増やさずに済みます。

この画面が何を表示するかは [curriculum.md](curriculum.md) にあります。

これらのセットアップは AMI に焼き込んでおきます。詳しくは[運用手順](operations.md)を参照してください。

### 権限

EC2 にはインスタンスプロファイルを付けます。ここに AgentCore のデプロイに必要な権限をまとめておくことで、受講者が自分の AWS 認証情報を持つ必要がなくなります。必要な権限は次のとおりです。

- AgentCore Runtime の作成・呼び出し
- `iam:CreateRole` ほかロール操作（`role/*BedrockAgentCore*` に限定）
- `iam:PassRole`（`role/AmazonBedrockAgentCore*` に限定）
- S3（`bedrock-agentcore-*` バケット）
- CloudFormation と CDK ブートストラップロールへの `sts:AssumeRole`
- CloudWatch Logs の読み取り
- SSM（Session Manager での接続用）

`agentcore deploy` は内部で AWS CDK を使ってデプロイするため、CloudFormation と CDK のブートストラップロールに対する権限が必要になります。この点は公式の devguide には書かれておらず、CLI のリポジトリ側のドキュメントに記載があります。

参考: [IAM Permissions for AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html) / [aws/agentcore-cli の PERMISSIONS.md](https://github.com/aws/agentcore-cli/blob/main/docs/PERMISSIONS.md)

### モデルの呼び出し

使うモデルは Amazon Nova 2 Lite です。ハンズオンでは受講者が思い思いにエージェントを動かすので、料金の安いモデルを選んでいます。入力が 100 万トークンあたり 0.30 USD、出力が 2.50 USD で、コンテキストは 1M トークンあります。

東京リージョンではオンデマンドの直接指定に対応していないため、推論プロファイル経由で呼びます。`jp.` から始まる日本国内完結のプロファイルか、`global.` から始まるグローバルのプロファイルのどちらかです。

```
jp.amazon.nova-2-lite-v1:0      東京と大阪で完結する
global.amazon.nova-2-lite-v1:0  グローバルにルーティングされる
```

雛形のコードには最初から推論プロファイル ID を書いておきます。受講者がモデル ID を素の `amazon.nova-2-lite-v1:0` で書くとエラーになり、初心者には原因が分かりにくいためです。Strands Agents では `BedrockModel` の `model_id` を差し替えるだけで済みます。

```python
from strands import Agent
from strands.models import BedrockModel

model = BedrockModel(model_id="jp.amazon.nova-2-lite-v1:0")
agent = Agent(model=model)
```

### 使えるモデルを絞るか

検証の段階では絞りません。実際に動かしてみないと受講者がどのくらいトークンを使うのか読めないため、まず制限なしで通して、本番前に改めて判断します。

絞りたくなったときのために、選択肢と制約を整理しておきます。まず前提として、エージェントが実際にモデルを呼ぶのは AgentCore Runtime の実行ロールで、このロールは CLI が自動生成するためポリシーを書き換えられません。公式のサンプルを見ると、自動生成される実行ロールは `foundation-model/*` を丸ごと許可する形になっています。つまり実行ロール側では絞れません。

| 方法 | 効き方と制約 |
|---|---|
| Bedrock のモデルアクセス | 有効にしていないモデルは呼べないので、ロールの権限に関係なく効く。ただし設定はリージョン単位なので、ハンズオンで使うリージョンは主催者自身の作業にも同じ制限がかかる |
| SCP | ロールが何であろうと上から効く。アカウントが AWS Organizations の配下にある必要がある |
| ハンズオン専用アカウント | 分離としては一番きれい。ただしクレジットの適用先が分かれるため、一括請求とセットで考える必要がある |
| EC2 のインスタンスプロファイル | 自分で書けるので絞れるが、効くのは受講者が EC2 から直接 Bedrock を叩く場合だけ。エージェント経由の呼び出しには効かない |

主催者が普段使うリージョンとハンズオンのリージョンを分ければ、モデルアクセスで絞っても自分の作業に影響しません。

### リージョン

ap-northeast-1（東京）を使います。AgentCore は 2025 年 10 月の GA 時点から東京に対応していて、Runtime・Memory・Gateway・Identity・Observability が揃っています。東京で使えないのは AgentCore Payments だけで、今回のハンズオンでは使いません。

参考: [Supported AWS Regions - Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html)

## そう決めた理由

### 受講者に AWS の認証情報を配らない

当初は SSM ポートフォワードで EC2 に到達する案でした。インバウンドをまったく開けずに済む点は優れていますが、受講者の手元に AWS CLI・Session Manager プラグイン・IAM の認証情報の 3 点が必要になります。初心者が 10〜30 人いる場では、この 3 点を揃えるところで開始直後の時間が溶けますし、会社支給の PC でプラグインをインストールできない参加者が出ます。

EC2 のインスタンスプロファイルに権限を持たせれば、受講者側の認証情報はそもそも要りません。マネジメントコンソールを使わない進め方にしているので、コンソールへのログインも不要です。この 2 つが揃うと、受講者に配るものが URL とパスワードだけになります。

### 入口を ALB にする

ブラウザだけで参加できるようにするには、EC2 の code-server にインターネットから到達できる必要があります。EC2 に直接パブリック IP でアクセスさせる方法もありますが、HTTPS にするには証明書を各インスタンスに配る必要があり、人数ぶんの手間がかかります。

ALB で TLS を終端すれば、証明書は ACM のワイルドカード 1 枚で足ります。EC2 側は HTTP のままでよく、セキュリティグループも ALB からの 1 経路だけを許可すれば済みます。

### AMI を焼く

user_data でセットアップを実行する方式だと、当日 30 台が同時にパッケージを取得することになり、起動から使えるまでに数分かかります。さらに、途中で失敗した数台のデバッグに主催者が張り付くことになります。

事前に 1 台を作り込んで AMI にしておけば、当日は起動するだけです。セットアップの成否は前日までに確定します。

### 手順書は S3 + CloudFront で配る

受講者が読む手順書は HTML 1 枚にして、非公開の S3 バケットから CloudFront（OAC）経由で配信します（Issue #48）。受講者に配る URL が code-server とハンズオン UI に手順書を加えた 3 つになるだけで、受講者の PC に何も入れなくてよい設計は変わりません。

Terraform のルートは受講環境（`terraform/`）と分けて `guide/terraform/` に置いています。手順書は前もって公開して当日まで置いておくもので、受講環境は当日に作って終わったら消すものなので、寿命が違います。同じ state に入れると、手順書だけ見たいときにも EC2 と ALB を作ることになります。ルートが 2 つになるぶん init が 1 回増えますが、その代わり apply と destroy を別々に打てます。

原稿は `docs/curriculum.md` から変換せず、受講者向けに別で書いています。curriculum.md は主催者の進行台本で、受講者が読むには情報が多いためです。内容の更新は `guide/publish.sh` で S3 に同期するだけにして、Terraform を触らずに済むようにしています。

### 後片付けは仕組みで担保する

EC2 と ALB は起動している限り課金されます。金額は小さくても、消し忘れて数日放置すると桁が変わります。受講者が `agentcore deploy` で作る Runtime やスタックは Terraform の管理外で人数ぶんバラバラに残るので、手順書だけに頼らず仕組みで担保します（Issue #17）。

本命は棚卸しスクリプト（`scripts/cleanup-participant-resources.sh`）です。名前が `handson` で始まるものだけを選んで一覧し、`--delete` を付けたときだけ消します。同じアカウントに別案件のリソースがあるため、タグではなく名前の接頭辞で絞っています。接頭辞は `agentcore.json` のプロジェクト名（`handsonPARTICIPANT` を起動時に `handsonuserNN` へ置換）で固定されているので、Runtime 名・スタック名・ロール名・ロググループ名がすべて同じ規則から派生します。

保険として、Terraform の変数 `handson_end_time` を 1 つ渡すと、その時刻に受講者ロールの Deny（`aws:CurrentTime` 条件）で Bedrock と Runtime の呼び出しを止め、EventBridge Scheduler の一回きりスケジュールで EC2 を停止し、ALB を削除します。Scheduler は universal target で API を直接呼ぶので Lambda は置きません。自動で行うのは「停止」までで、最終的な削除は人が棚卸しスクリプトと `terraform destroy` まで通します。

### Terraform の state は S3 に置く

state を手元にしか置かないと、作業しているマシンが当日使えなくなったときに `terraform destroy` の経路が塞がり、別のマシンや別の人が apply / destroy を引き継げません。ロックも効かないので、同じ state に二重に apply する事故も防げません。当日は 30 人ぶんのリソースを Terraform で持つので、state は S3 に置きます（Issue #40）。

置き場は `scripts/build-ami.sh` が使っている資材バケットの `terraform-state/` です。state 専用のバケットを分ける案もありましたが、数十 KB のファイル 1 つのためにバケットを増やすより、ハンズオン由来の S3 を 1 つにまとめておくほうが後片付けでも把握しやすいと判断しました。ロックは Terraform 1.10 以降の `use_lockfile` で取り、DynamoDB は使いません。手順は [docs/operations.md](operations.md) の「Terraform の state を S3 に置く」にあります。

### インスタンスタイプは実測で t4g.small にした

t4g.small（2 vCPU / 2GB）と t4g.medium（2 vCPU / 4GB）で `agentcore deploy` を実測しました（2026-09-06、Issue #15）。deploy は SSM 経由で `agentcore deploy --yes --target default` を流し、裏で `vmstat 5` を取っています。

| | t4g.small（新規スタック） | t4g.medium（新規スタック） | t4g.medium（再 deploy） |
|---|---|---|---|
| 所要時間 | 99 秒 | 112 秒 | 27 秒 |
| CPU user 平均 | 26% | 24% | 47% |
| iowait 平均 / 最大 | 3% / 24% | 10% / 52% | 11% / 17% |
| free の最小値 | 210MB | 2114MB | 1964MB |

所要時間のほとんどは CloudFormation の完了待ちで、CPU が張り付くのは最初の 30 秒（CDK の synth と CodeZip の作成）だけです。small で free が 210MB まで落ちてもファイルキャッシュが 660MB あり、メモリ不足ではありません。medium の新規で iowait が高いのは、AMI から起動した直後に EBS がスナップショットから読み込んでいる最中だったためで、インスタンスタイプの差ではありません。

t4g.medium は vCPU 数も CPU のベースラインも small と同じで、増えるのはメモリだけです。メモリが足りているので選ぶ理由がなく、30 人 × 5 時間で EC2 代が倍（3.24 USD → 6.48 USD）になるだけでした。加えて t4g.small には 2026 年末までの無料トライアル（月 750 時間）があり、medium は対象外です。条件は [docs/operations.md](operations.md) の「t4g.small の無料トライアル」にまとめています。

code-server に同梱される Copilot 拡張（`github.copilot-chat`）は起動直後から 130MB ほど使うので、AMI を作るときにディレクトリごと削除しています。code-server の CLI に拡張を無効化するフラグは無く、`chat.disableAIFeatures` も画面から隠すだけでプロセスは止まらないためです。

## 検討して採用しなかった案

| 案 | 採用しなかった理由 |
|---|---|
| SSM ポートフォワードで受講者が接続する | 受講者の PC に CLI とプラグインと認証情報が必要になる。初心者の多い場では開始直後の脱落が読める |
| 受講者それぞれの AWS アカウントを使う | Bedrock のモデルアクセス有効化や CDK ブートストラップを全員にやってもらう必要があり、当日の変動要因が増える |
| 1 台の EC2 を複数人で共有する | 同じディレクトリを触って壊し合う。AgentCore Runtime の名前も衝突する |
| user_data で毎回セットアップする | 当日の待ち時間と失敗リスクが人数ぶん増える |
| EC2 に直接パブリック IP でアクセスさせる | 人数ぶんの証明書配布が必要になる。HTTP のままだとパスワードが平文で流れる |
| 講師が Runtime を 1 つ立てて全員がそこを呼ぶ | 同時アクセス自体はクォータ的に成立するが、30 人分のログが 1 つのロググループに混ざり、自分の実行を探すところから始まってしまう。用意されたエンドポイントを呼ぶだけでは自分事にもならない |
| Bedrock の API キーを受講者に配る | API キーは Bedrock と Bedrock Runtime の API にしか使えず、AgentCore 系の API は対象外なので deploy も呼び出しもできない。そもそも全員が同じアカウントで動かすため、コストは主催者のアカウントに乗る |

## 制約と既知の問題

**AgentCore Runtime の実行ロールを事前に作って渡せません。** AgentCore CLI は実行ロールを自分で作る作りになっていて、設定ファイルに `roleArn` を書いても deploy 時に無視されます。CLI のリポジトリに Issue が上がっていますが、本ドキュメント作成時点では解決していません。このため、EC2 のインスタンスプロファイルにロール作成権限を持たせる前提で組んでいます。

参考: [aws/agentcore-cli Issue #870](https://github.com/aws/agentcore-cli/issues/870)

**受講者の権限を厳密に絞ることはできません。** `agentcore deploy` は CDK 経由でデプロイするため、CDK のブートストラップで作られる CloudFormation 実行ロールを引ける必要があります。このロールはデフォルトで AdministratorAccess を持ちます。つまり、受講者に渡す EC2 の権限を絞っても、CDK 経由で強い権限を借りられる状態が残ります。

ハンズオンは主催者のアカウントに信頼できる参加者を招く前提なので運用上は問題になりませんが、同じ構成を不特定多数に開く用途には向きません。ブートストラップ時に `--cloudformation-execution-policies` で実行ロールのポリシーを差し替える方法はありますが、アカウント全体の CDK 環境に影響するため、この環境では踏み込みません。

**AgentCore Runtime は ARM64 のみです。** EC2 も ARM64 に揃えています。x86 の AMI を使うと、ローカルでの動作とデプロイ後の動作がずれる可能性があります。

## これからやること

作業は Issue で管理しています。着手順は次のとおりです。

| # | 内容 |
|---|---|
| 1 | AgentCore Runtime のストリーミング応答を確認する |
| 2 | 1 人分の環境を Terraform で作る |
| 3 | Strands Agent の雛形を作る |
| 4 | ハンズオン UI を作る |
| 5 | 受講者用の AMI を作る |
| 6 | 受講者数ぶんに展開する |
| 7 | 事前準備を実施して手順を確定させる |
| 8 | リハーサルを実施する |

1 を先にやるのは、ハンズオンの前半と後半で同じ画面を使う設計がそこに依存しているためです。ここが崩れると 4 の作りが変わります。

受講者数の確定とコストの実測は、6 と 8 のなかで詰めます。
