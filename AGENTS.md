# AgentCore ハンズオン環境 — 作業メモ

Amazon Bedrock AgentCore のハンズオン環境を Terraform で構築するプロジェクトです。プロジェクトの概要は [README.md](README.md)、構成の詳細は [docs/architecture.md](docs/architecture.md)、運用手順は [docs/operations.md](docs/operations.md) を参照してください。

## 現在の状況

最終更新: 2026-10-15

### 決まっていること

- 受講者は 10〜30 人。主催者の AWS アカウント 1 つに全員が入る
- 受講者に AWS の認証情報は配らない。EC2 のインスタンスプロファイルで `agentcore deploy` まで通す
- 入口は ALB + HTTPS。ホスト名（`userNN.handson.<ドメイン>`）で受講者ごとの EC2 に振り分ける
- DNS は Cloudflare。ワイルドカードの CNAME を ALB に向ける（プロキシは無効）
- EC2 は t4g.small / Amazon Linux 2023 / ARM64。1 人 1 台。当日、誰かの環境が動かなくなったときは、その場で隣の人の環境を 2 人で使うことがある（Terraform の変更は要らない）。ルートボリュームは 15GiB。t4g.medium と比べて `agentcore deploy` の所要時間に差が無かったので small のまま（Issue #15 で挙動を比べて決めた）
- 開発環境は AMI に焼いておく。user_data で毎回セットアップはしない
- リージョンは ap-northeast-1（東京）
- モデルは Amazon Nova 2 Lite。東京は In-Region 非対応なので `jp.amazon.nova-2-lite-v1:0` を使う
- 検証の段階ではモデル制限をかけない。本番前に改めて判断する（選択肢と制約は docs/architecture.md にまとめた）
- Bedrock の利用料は主催者のアカウントに乗るので、アカウントに付いているクレジットがそのまま効く
- IaC は Terraform
- 目標時期は 2026 年 10 月末
- ハンズオンは「手元で動かす → ツールを足す → 忘れることを体験する → Runtime に載せる → 振り返る」の 5 ステップ（[docs/curriculum.md](docs/curriculum.md)）
- サービスの名前は先に説明せず、受講者が困ったあとに出す
- **トレースは自作のハンズオン UI だけで見せる**。前半のローカル実行も後半の Runtime 実行も同じ画面。汎用のトレース UI も CloudWatch のコンソールもハンズオン中は開かない（初学者には情報が多すぎる / マネコンのログインが要る）
- AgentCore Runtime へのデプロイは受講者が各自行う（1 人 1 つ）。共有 Runtime はログが混ざるため不採用
- code-server のパスワードは受講者ごとに変える。Terraform で生成して user_data で渡す
- エージェントの題材は社内の備品貸出の案内。ツールを 1 つ足す体験がしやすい題材にした
- Harness は振り返りで名前と位置づけを話すだけにする。自分でループを書いたあとに出すから意味が伝わる（`harness.json` は用意しておく）
- Amazon Linux 2027 は preview なので使わない。当日パッケージが入らないリスクを取らない
- ワークスペース（受講者の EC2 に置くファイル一式。`/home/handson/workspace` に展開する）は `handson-agent/`（受講者が触る雛形）と `handson-ui/`（主催者側の UI）に分ける。受講者が code-server を開いたときに、触るファイルだけが平置きで見える形にする。裏方の `events.py` は `handson-agent/lib/` に寄せる
- ツールはデータ（dict / list）を返し、日本語にするのはモデルの仕事にする。ツールの結果とモデルの答えが同じ文になると、モデルが何を足したのか見えないため
- ハンズオン UI の見せ方は、ループの 1 周を「モデルを呼んで、ツールを実行して、結果を受け取るまで」とし、周ごとに折りたためる見出しで区切る。色は 3 つだけで、緑はループの入口と出口（お題の質問と最終的な答え）、青紫はモデルに入るもの、茶色寄りのオレンジはモデルかツールから出てくるもの（Issue #60 で手順書サイトと同じ紙色のパレットに揃えた。以前は白地に青緑・青・オレンジ）。周の境目では同じカードを重複して出し、色をオレンジから青に切り替えて「出てきたものを次は入れる」を見せる
- UI は常にライトテーマ、端末のフォントだけを使い、本文 16px・補助 13px 以上、白地でコントラスト比 4.5 以上を保つ（プロジェクターで見にくかったため）
- UI のサーバーは `uvicorn --reload --reload-dir ../handson-agent` で起動し、受講者が `tools.py` を保存したら画面のツール一覧が追随するようにする
- 後片付けは仕組みで担保する（Issue #17、実装済み）。名前が `handson` で始まるものだけを選んで消す棚卸しスクリプト `scripts/cleanup-participant-resources.sh` を本命に、終了時刻 `handson_end_time` を Terraform の変数で渡して IAM の Deny・EC2 停止（EventBridge Scheduler）・ALB 削除を時刻で発火させる。時刻後は apply せず destroy の一方向。Budgets は既存のものを使う
- モデルは比較のうえ Nova 2 Lite に据え置く。Nova Micro や旧 Nova Lite は安いが世代が古く、オープンモデルは Converse API でのツール呼び出しが未確認。下がる幅も最大 1 USD 程度で、ツール選択の確実さを優先した
- 受講者には code-server と UI（/proxy/3000/）の 2 つの URL を配り、workspace の README を起動時に開いて導線にする（Issue #36）
- Terraform の state は S3（build-ami.sh の資材バケットの `terraform-state/`）に置き、ロックは Terraform 1.10 以降の `use_lockfile` で取る。DynamoDB は使わない。バケット名は SOPS で暗号化した `terraform/secrets.enc.env` で渡し、ラッパー `scripts/tf.sh` が `init` のときに `-backend-config` として渡す（Issue #40、#79）
- 受講者向けの手順書は Astro Starlight の静的サイト（`guide/`。本文は `guide/src/content/docs/` の MDX。原稿は curriculum から変換せず別で書く）を S3 非公開 + CloudFront OAC で配信する。S3 + OAC はフォルダ形式の URL で index.html を補わないので `build.format: 'file'` で `step1.html` のように出力し、本文中のリンクも `.html` 付きで書く。テーマはプロジェクター向けに常にライト固定（ThemeProvider / ThemeSelect を差し替え）。図は docs/images の drawio と同じ流儀で描いて `guide/public/images/` にコピーする（Issue #51）。Terraform のルートは寿命が違うので `terraform/guide/` に分け（受講環境は `terraform/handson/`）、state は同じバケットの別キー。中身の更新は `guide/publish.sh`。独自ドメインは `guide_hostname` を指定したときだけ（証明書は us-east-1 でホスト名単体を発行）（Issue #48）
- 手順書の更新は GitHub Actions で自動配信する（`guide/**` が main に入ったら `npm ci && npm run build` して `guide/dist` を s3 sync + キャッシュ削除。`participants/*` は sync の対象外にして消さない）。認証は OIDC で、ロールは `terraform/guide` が作り、このリポジトリの main からだけ assume できる。sub は ID 無しと ID 付き（immutable subject claim）の両方を許可する。バケット名などは GitHub の Variables に置く（Issue #52）
- 受講者情報（userNN ごとの URL とパスワードの表）は手順書サイトの `participants.html` に出す。中身の `participants/data.json` は git に入れず、`terraform/handson` が S3 のオブジェクトとして置く（`participants.tf`。`secrets.enc.json` の `guide_bucket_name` に手順書のバケット名を書いたときだけ）。apply で置かれ destroy で消えるので、受講環境と表の寿命が揃う。以前はスクリプト（`publish-participants.sh`）で置いていたが、destroy のあとに消し忘れて古い表が残ったので改めた（Issue #76）。`/participants*` だけ CloudFront Function（viewer-request）の Basic 認証で守り、ユーザー名と合言葉は `terraform/guide` の変数（SOPS で暗号化した `secrets.enc.json`）で渡す。合言葉 1 つで全員分が見える形はリュウキ判断で許容（当日その場で口頭で伝える）（Issue #58）
- Cloudflare の `*.<base_domain>` の CNAME は Terraform（cloudflare プロバイダー v5 の `cloudflare_dns_record`）で管理し、ALB の作り直しに自動で追随させる。API トークンは環境変数 `CLOUDFLARE_API_TOKEN` で渡し、ゾーン ID だけ tfvars に書く。実体は SOPS で暗号化した `terraform/secrets.enc.env`（トークン）と `secrets.enc.json`（ゾーン ID）で、`scripts/tf.sh` が実行中だけ渡す（Issue #79）。証明書の検証用 CNAME は手で入れたまま管理外にする（Issue #30）
- モデルや Runtime の呼び出しが失敗したら、UI のサーバーが例外を捕まえて画面に内容を出す。手元実行でも Runtime 経由でも同じ。混み合い（スロットリング）のときは「少し待ってから、もう一度送ってください」を先に出す。Bedrock の上限は 30 人で足りるが、AgentCore の新しいセッションの作成は 1 秒あたり 25 までなので、ステップ 4 は講師が一斉に送らせず、準備できた人から送ってもらう（Issue #75）
- git 管理外だった設定ファイル（ドメイン、証明書 ARN、Cloudflare の API トークンなど）は SOPS で暗号化してリポジトリに入れる。鍵は age。AWS KMS は鍵 1 本ごとに月額がかかり、IAM Identity Center の一時的な認証情報で SOPS がうまく動かない報告もあるため使わない。SOPS が HCL を扱えないので tfvars は JSON にして暗号化する（`terraform/handson/secrets.enc.json` など）。Terraform には `sops exec-env` / `sops exec-file` で渡し、復号した値が state に残る SOPS の Terraform プロバイダーは使わない。手順が長くなるのでラッパー `scripts/tf.sh` を用意した（Issue #79）
- 保存した plan ファイルには変数の値が平文で入る。よく使う名前（`*.tfplan`、`*.plan`、`tfplan`）は `.gitignore` で除外し、`scripts/tf.sh` は `-out` のときに注意を出す。名前は自由に付けられるので完全には防げないが、pre-commit フックまでは入れない（#80 のレビューで判断）
- 受講者情報の表は EC2 の作成を待ってから置く（`depends_on`）。ALB のヘルスチェックが通るまでは待たない。表が数分早く出てもパスワードは最終的な値で、当日は主催者が動作確認してから配るため（#78 のレビューで判断）

### できているもの

すべて main にマージ済み（2026-09-27 時点）。

- 構成図とドキュメント（README.md、docs/architecture.md、docs/curriculum.md、docs/operations.md、docs/images/ の構成図・流れ図・Terraform の管理体系図）
- Strands Agent の雛形（`handson-agent/`）。モデル呼び出し、Nova 2 Lite のツール選択、Runtime へのデプロイまで確認済み。ツールはデータ（dict / list）を返す
- ハンズオン UI（`handson-ui/`、React + Vite + FastAPI）。周ごとの見出しと折りたたみ、入力と出力の 2 色、ツールの結果の JSON 表示、Markdown 記号の抑制、ラベルの補足。手元と Runtime のどちらでも同じ画面で動く。モデルや Runtime の呼び出しが失敗したら、内容を画面に出す（混み合いのときは日本語の案内付き、#75）
- 受講環境のセットアップスクリプト（`scripts/setup-instance.sh`）と、AMI を焼く一括スクリプト（`scripts/build-ami.sh`、Issue #19）。同梱の Copilot 拡張はディレクトリごと消している（Issue #15）。今の AMI は 2026-09-27 に作り直した `ami-0222b0438e7a64a4d`（agentcore-handson-20260927-2049。#46、#60、#75 の変更が入っている。#91）で、`terraform/handson/secrets.enc.json` の `ami_id` がこれを指す
- 受講環境の Terraform（`terraform/handson/`）。AMI 前提で、`ami_id` を必須で受け取り、user_data は受講者固有の値を差し込むだけ。Cloudflare のワイルドカード CNAME も一緒に作る（Issue #30）。state は S3、ロックは `use_lockfile`（Issue #40）
- 後片付けの仕組み（Issue #17）。棚卸しスクリプト `scripts/cleanup-participant-resources.sh`（一覧モードは確認済み、`--delete` は未確認）と、`handson_end_time` で発火する Deny・EC2 停止・ALB 削除。EC2 停止と ALB 削除は実機で発火を確認した（2026-09-17。下の記録参照）。Deny は未確認
- 受講者向けの手順書（`guide/`、Issue #48。#51 で Astro Starlight に作り直し、mcks.log と同じ紙色のパレット、セクションごとのページ + サイドメニュー + 図 4 枚 + 画像の拡大表示）。受講者情報ページ `participants.html` と `/participants*` の Basic 認証は #58 で追加し、apply 済み（2026-09-07。認証なしは 401、他のページは今までどおり）。パスワードの列の見切れを直し、コピーボタンを付けた（#65。2026-09-23 に配信済み）。表の中身は今は置いていない（受講環境を立てると置かれる）。S3 非公開 + CloudFront OAC で配信し、`https://guide.handson.<base_domain>/` で HTTPS 200、HTTP は 301、S3 直アクセスは 403 まで確認済み。証明書は us-east-1 でホスト名単体を発行し、検証用と本体の CNAME は Terraform が Cloudflare に入れる。中身は GitHub Actions（OIDC、Issue #52）か `guide/publish.sh` で同期する。環境は本番まで立てたままにする
- 設定ファイルの暗号化（SOPS、Issue #79）と、復号しながら terraform を動かす `scripts/tf.sh`。秘密鍵（`~/.config/sops/age/keys.txt`）は 2026-10-13 にマシンの外へ控え、公開鍵が `.sops.yaml` と一致することを確かめた。平文の設定ファイルと古いローカルの state は 2026-09-23 に手元から消した。暗号化した設定だけで `scripts/tf.sh guide plan` が No changes、`scripts/tf.sh handson plan` が 34 件の作成予定（2 人分、終了時刻なし）になることを確認済み
- 受講者の EC2 全台に SSM で同じコマンドを一斉に流すスクリプト `scripts/run-on-participants.sh`（#93）。`deploy`（全台で同時に `agentcore deploy`）と `model`（全台で Nova 2 Lite を 1 回呼び、Deny されるかも見る）の 2 つ。偽の aws コマンドで流れを確かめ、モデル呼び出しのコマンドは手元から Bedrock に通した。実機の EC2 ではまだ流していない
- コストの試算。30 人 5 時間で約 3.0 USD（t4g.small の無料トライアル適用時。無ければ約 6.2 USD。パブリック IPv4 の料金を #82 で足した。内訳は docs/operations.md）。東京で使えるモデルの単価比較は Nova 2 Lite 据え置き

通し確認の記録（2026-09-05〜06）。

- 1 人分の apply（26〜27 リソース）で code-server にログインでき、`/home/handson/workspace` が開いた状態で始まる。`agentcore deploy` が受講者の権限で 1 行で通る。ハンズオン UI から手元と Runtime のどちらでも同じ画面で動く
- Cloudflare の CNAME は ALB の作成直後に新しい DNS 名へ向き、destroy で一緒に消える。検証用 CNAME だけが残る
- AMI `ami-0e6e145f65e038cd9`（agentcore-handson-20260906-1805、arm64、15GiB）で t4g.small と t4g.medium の `agentcore deploy` を比べ、所要時間が変わらなかった（small 99 秒、medium 112 秒）ので small のまま。表と考察は docs/architecture.md の「インスタンスタイプ」にある。Copilot 拡張の削除は効いている（プロセス 0、再起動後の使用メモリ 301MB）
- Runtime 名（`handsonuserNN_agent`）と CloudFormation スタック（`AgentCore-handsonuserNN-default`）が受講者ごとに分かれることを 2 人分で確認した（Issue #31）
- 確認後の環境と Runtime のスタック、古い AMI は削除済み。Cloudflare の API トークンは `terraform/secrets.enc.env`（SOPS で暗号化）に置き、`scripts/tf.sh` が実行中だけ渡す（Issue #79。当時は git 管理外の `~/.config/agentcore-handson/cloudflare.env` を terraform の前に `source` していた）

後片付けの仕組みの確認記録（2026-09-17〜18）。

- 2 人分（user01、user02）を `handson_end_time = 2026-09-17T13:00:00+09:00` で apply し、時刻を過ぎたあとに見ると ALB とリスナーが消え、EC2 は 2 台とも stopped になっていた。EventBridge Scheduler の 2 つのスケジュール（EC2 停止、ALB 削除）は発火後に自分で消えていて、`plan -destroy` では state 40 件のうち ALB 系と Scheduler の 7 件が「既に無い」扱いになった
- 受講者ロールの Bedrock Deny が効くかは見ていない（次に受講環境を立てたときに確認する）
- 停止した EC2 は EBS の課金が続くので、2026-09-18 に `terraform destroy` で残り 30 件を消した。state は空、EC2 は terminated、孤立した EBS ボリュームは無し。手順書サイトは残した（HTTPS 200 を確認）
- AMI `ami-0e6e145f65e038cd9` は、そのあとのワークスペースの変更が入っていなかったので 2026-09-27 に作り直した（#91）。古い AMI は、新しい AMI で受講環境が動くと確かめるまで残している

協力者とのお試しの記録（2026-10-13〜15。#97）。

- 日程は 10/5 から延期を重ねて 2026-10-14（水）14:00〜16:00 JST になり、受講環境は 1 台（user01）にした。終了時刻は 16:15
- 前日の 10/13 20:12 JST に apply した（34 件）。code-server へのログイン、UI の画面とツール一覧、user01 からのモデル呼び出し（allowed）、ALB のヘルスチェック、受講者情報の表まで確かめた
- 当日は 15:17 JST に user01 から `agentcore deploy` された（Runtime の CloudFormation スタックの作成時刻）
- 16:15 JST に EC2 の停止と ALB の削除が発火し、2 つのスケジュールは自分で消えた
- 10/15 に止まった user01 を一度だけ起こして `scripts/run-on-participants.sh model --only user01` を流し、`denied`（AccessDeniedException、explicit deny）になった。終了時刻で起きる 3 つ（EC2 停止・ALB 削除・Bedrock の Deny）を、すべて実機で確かめたことになる。確認のあと EC2 は止め直した
- `scripts/tf.sh handson destroy` で 28 件を消した（ALB とリスナー、スケジュールの 6 件はもう無かった）。受講者情報の表（`participants/data.json`）も一緒に消えた。EC2 は terminated、孤立した EBS は無し。手順書サイトは HTTPS 200 のまま
- 古い AMI `ami-0e6e145f65e038cd9` とスナップショット `snap-0ea4ae3828f31b220` を消した。残っている AMI は `ami-0222b0438e7a64a4d` だけ
- 棚卸しスクリプトの `--delete` は、Claude Code の auto モードの判定で止められて流せていない。残っているのは、中身が CDK のメタデータだけの空のスタック `AgentCore-handsonuser01-default` と、ロググループ `/aws/bedrock-agentcore/runtimes/handsonuser01_agent-…` の 2 つ（課金はほぼ無い）。リュウキがターミナルから流す
- 暗号化した設定から `handson_end_time` を外した（過ぎた時刻のまま apply すると Deny がすぐ効くため）。`participants` は user01 のまま

30 人分に広げる前の事前調査の記録（2026-09-23。詳細は Issue #6 のコメント）。

- EC2 の vCPU 上限（東京の Running On-Demand Standard、`L-1216C47A`）が 32 で、30 人分の 60 に足りない。80 への引き上げを申請し、2026-09-23 に承認された（サポートの審査を経て約 1 時間）
- Bedrock（Nova 2 Lite のクロスリージョン推論は 1 分あたり 200 リクエスト・800 万トークン）、AgentCore（Runtime 100、アクティブなセッション 2,500）、ALB（ルールとターゲットグループが各 100）は 30 人で足りる。`agentcore deploy` は CodeZip なので CodeBuild と ECR は使わない
- Terraform のコードは 30 人にしても直す必要がある箇所は無い。EC2 は全員が 1 つの AZ に入っていたので、名前の番号の偶数・奇数で 2 つの AZ に分けた（Issue #83）

### 次の一歩

AWS の変更操作（AMI 作成、apply、destroy）は `aws login` の認証情報が要るので、リュウキがブラウザで認証できるタイミングで進める。

1. 30 人分を試しに apply する（#6）。お金がかかる時間を約 25 分に抑える（終了時刻を apply の 25 分後にし、確認と片付けは EC2 が止まったあとにやる。費用の目安は 0.1〜0.5 USD）。`participants` を user01〜user30 にし、主に 30 人がほぼ同時に `agentcore deploy` したときの待ち時間（CloudFormation の API にはアカウント単位の呼び出し上限がある）を確かめる。一斉の deploy は `scripts/run-on-participants.sh` で流す（手順は docs/operations.md の「人数ぶんで試す」、段取りは #6 のコメント）。お試しで確かめられなかった棚卸しスクリプトの `--delete` も、ここで確かめる
2. 本番の前に、受講者情報ページの合言葉を新しい値に変える（`sops edit terraform/guide/secrets.enc.json` で `participants_password` を書き換え、`scripts/tf.sh guide apply`）

当日の運営（事前準備、リハーサル）はこのリポジトリの範囲外にした（Issue #7、#8 はクローズ）。

### 未確定

- `aws login` の認証情報が 15 分ほどで更新に失敗して切れる（AWS CLI 側の既知の不具合と同じ症状）。`terraform apply` や `build-ami.sh` のような長い操作は直前にログインし直す。認証方式そのものの見直しはこのプロジェクトの外で扱う
- 本番でモデル制限をどうかけるか（検証の段階ではかけない方針）
- UI のサーバーを本番でも `--reload` 付きで動かすか。1 人 1 台なので負荷は問題ないが、保存すると再起動する挙動を受講者に説明する必要がある

## 作業のルール

- 作業の区切りごとに、この「現在の状況」を更新してコミットする。別の場所でセッションを再開しても状況が分かるようにするため
- `handson-agent/`、`handson-ui/`、`agentcore/`、`scripts/setup-instance.sh` を変えたら、受講環境を立てる前に AMI を作り直す（`scripts/build-ami.sh`）。受講者の EC2 には AMI を作った時点の中身が入り、user_data では配り直さないため
- 将来的にパブリックリポジトリにする想定で書く。個人名、社名、内部だけで通じる文脈は書かない
- ドメイン名などの環境固有の値はドキュメントに直接書かず、`example.com` のような例示に置き換える。実際の値は Terraform の変数に持たせる
- コミットメッセージは 1 行の日本語で簡潔に

## 前提知識

このプロジェクトを触るうえで踏まえておく必要がある制約です。詳細は [docs/architecture.md](docs/architecture.md) の「制約と既知の問題」にあります。

- `agentcore deploy` は内部で AWS CDK を使う。アカウント・リージョンごとに `cdk bootstrap` が必要
- AgentCore Runtime の実行ロールを事前に作って渡すことは現状できない（CLI が自動生成する）
- AgentCore Runtime は ARM64 のみ
- 東京リージョンでは Nova 2 Lite も含めオンデマンドの直接指定に非対応。推論プロファイル経由で呼ぶ
- Bedrock の API キーは bedrock / bedrock-runtime の API 専用で、AgentCore 系の API には使えない
- 受講者が `agentcore deploy` で作ったリソースは Terraform の管理外なので、後片付けが別途必要
