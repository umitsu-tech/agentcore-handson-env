# 構成の詳細

![構成図](images/architecture.png)

ハンズオンで何をやってもらうかは [curriculum.md](curriculum.md) にあります。

## 全体像

受講者はブラウザで `user01.handson.example.com` のような自分専用の URL を開きます。リクエストは Internet Gateway から Application Load Balancer に入り、ALB が HTTPS を終端したうえで、ホスト名を見て受講者ごとの EC2 に転送します。EC2 の上では code-server が待ち受けていて、パスワードを入力するとブラウザ上に VS Code の画面が出ます。

受講者はその VS Code で Strands Agent の雛形を編集し、ターミナルから `agentcore deploy` を実行します。コードは ZIP にまとめられて S3 に置かれ、AgentCore Runtime がそれを読み取ってマネージドな microVM 上でエージェントを起動します。デプロイが終わったら、同じ画面のチャット UI からエージェントを呼び出して動作を確認します。エージェントの内部では Amazon Bedrock の基盤モデルが呼ばれます。

## コンポーネント

### ネットワーク

VPC にパブリックサブネットを 2 つの AZ に用意します。ALB は 2 AZ 以上のサブネットを要求するため、AZ は 2 つ必要です。

EC2 もパブリックサブネットに置き、パブリック IP を付けます。インターネットへの下り通信（パッケージの取得、AWS API の呼び出し）が Internet Gateway 経由で通るため、NAT Gateway が要りません。NAT Gateway は起動している間ずっと課金されるので、数時間で捨てる環境では避けたいリソースです。

EC2 のセキュリティグループは、ALB のセキュリティグループからの 8080 番だけを許可します。SSH は開けません。インターネットから EC2 に直接届く経路はありません。

### 入口（ALB と証明書）

ALB は HTTPS:443 のリスナーを持ち、ACM で発行したワイルドカード証明書（`*.handson.example.com`）で TLS を終端します。証明書は 1 枚で受講者全員ぶんのサブドメインをまかなえます。HTTP:80 で来たリクエストは 443 にリダイレクトします。

リスナールールはホストベースで、`user01.handson.example.com` を受講者 01 のターゲットグループに、`user02...` を 02 に、という形で振り分けます。受講者を増やしてもルールとターゲットグループが増えるだけで、ALB は 1 つのままです。

DNS は Cloudflare で管理します。`*.handson.example.com` の CNAME を ALB の DNS 名に向けるレコードを 1 本引けば、サブドメインが何個あっても解決します。Cloudflare のプロキシ（オレンジクラウド）はワイルドカードでは有料プランが必要になるため、DNS only（グレークラウド）で運用します。TLS は ALB 上の ACM 証明書がそのまま使われます。

ACM の証明書検証も DNS 検証なので、Cloudflare に検証用の CNAME を 1 本追加します。

### 受講者の作業環境（EC2）

- インスタンスタイプ: t4g.small（ARM64 / AWS Graviton）
- OS: Amazon Linux 2023
- 1 人 1 台

ARM64 を選んでいるのは、AgentCore Runtime が ARM64 でしか動かないためです。ローカルでの動作確認とデプロイ先のアーキテクチャを揃えておくと、受講者が踏むトラブルが減ります。

EC2 には次のものを入れておきます。

- code-server（8080 番。ブラウザ上の VS Code）
- ハンズオン用のチャット UI（3000 番。code-server の `/proxy/3000/` 経由で開く）
- Strands Agent の雛形プロジェクト
- AgentCore CLI（`@aws/agentcore`）、AWS CDK、AWS CLI、uv、Node.js、Python

チャット UI を ALB のルールで別に公開せず、code-server が持つポート転送機能（`/proxy/<ポート番号>/`）を通す形にしています。ALB のリスナールールを増やさずに済みます。

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

## まだ決めていないこと

- 受講者数の確定（10〜30 人の想定）
- code-server のパスワードを受講者ごとに変えるか、全員共通にするか
- ハンズオンの教材（Strands Agent の雛形とチャット UI）の中身
- コストの実測（EC2 の台数 × 時間、ALB の稼働時間で試算する）
- 当日のリハーサルをいつ行うか
