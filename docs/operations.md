# 運用手順

開催前の準備、当日の流れ、終わったあとの片付けをまとめます。

## 1. 事前準備（初回だけ / 前日までに）

### Bedrock のモデルアクセスを有効にする

ハンズオンで使うリージョンで、Nova 2 Lite のモデルアクセスを有効にします。有効化はアカウント単位なので 1 回で済みます。

ここで有効にするモデルを絞ることが、そのまま使えるモデルの制限になります。有効にしていないモデルは呼び出せないので、他のモデルを使われたくないなら有効化は必要最小限にしておきます。

### CDK をブートストラップする

`agentcore deploy` は内部で AWS CDK を使うため、アカウントとリージョンの組み合わせに対して 1 回ブートストラップが必要です。

```bash
npx cdk bootstrap aws://<アカウントID>/ap-northeast-1
```

これを事前にやっておかないと、受講者が最初の `agentcore deploy` で失敗します。

### ACM で証明書を発行する

`*.handson.example.com` のワイルドカード証明書を、ALB を置くリージョンで発行します。検証方法は DNS 検証を選び、表示された検証用の CNAME を Cloudflare に追加します。証明書の状態が「発行済み」になるまで待ちます。

### AMI を作る

`scripts/build-ami.sh` を実行します。ワークスペースを tar.gz にして S3 に上げ、EC2 を 1 台起動して `scripts/setup-instance.sh` を流し、再起動後に code-server とハンズオン UI が動いていることを確認してから AMI を作り、EC2 を消すところまで一気にやります。

```bash
aws login                               # 一式で 15 分ほどかかる。セッションは 1 時間で切れるので直前に
scripts/build-ami.sh                    # 既定は t4g.small / ルートボリューム 15GiB
scripts/build-ami.sh --volume-size 20   # サイズを変えて試すとき
scripts/build-ami.sh --prune            # 古い AMI とスナップショットも消すとき
```

終わると新しい AMI ID が表示され、`terraform/terraform.tfvars` があれば `ami_id` を書き換えます。

AMI には次のものが入ります。

- code-server（8080 番で待ち受け）
- ハンズオン UI（3000 番。エージェントの動きを可視化する画面）
- Strands Agent の雛形プロジェクト
- Node.js、Python、uv、AWS CLI、AWS CDK、AgentCore CLI（`npm install -g @aws/agentcore`）

スクリプトが確認するのは code-server の `/healthz` とハンズオン UI の `/api/context` が応答することまでです。`agentcore deploy` が最後まで通ること、デプロイしたエージェントをハンズオン UI から呼んで動きが画面に出ることは、Terraform で 1 台立ててから確認します。

### Terraform の state を S3 に置く

Terraform の state は手元ではなく S3 に置きます。当日 30 人ぶんのリソースを Terraform で持つので、作業しているマシンが使えなくなっても別のマシンから `terraform destroy` を打てるようにするためです。置き場は `scripts/build-ami.sh` が資材置き場に使っているバケット（`agentcore-handson-assets-<アカウントID>`）の `terraform-state/` で、バケットは分けません。ロックは Terraform 1.10 以降の `use_lockfile`（S3 の条件付き書き込み）で取るので、DynamoDB のテーブルは要りません。

Terraform は 1.10 以降が必要です。Homebrew の `terraform` は 1.5.7 で止まっているので、HashiCorp の tap から入れます。

```bash
brew uninstall terraform            # Homebrew 本体の 1.5.7 が入っている場合
brew install hashicorp/tap/terraform
terraform version                   # 1.10 以降であること
```

バケットにはバージョニングを有効にしておきます（state を戻せるように）。`build-ami.sh` が作ったバケットは無効のままなので、初回に 1 度だけ有効にします。

```bash
aws s3api put-bucket-versioning --bucket agentcore-handson-assets-<アカウントID> --versioning-configuration Status=Enabled
```

バケット名にはアカウント ID が入るので、`terraform/versions.tf` には書かず、`terraform/backend.hcl`（git 管理外）で渡します。`backend.hcl.example` を写して作り、`init` のときに指定します。

```bash
cd terraform
cp backend.hcl.example backend.hcl   # bucket をアカウントの値に直す
terraform init -backend-config=backend.hcl
```

手元に `terraform.tfstate` が残っている状態から移す場合は `terraform init -migrate-state -backend-config=backend.hcl` で S3 へコピーされます。

別のマシンで引き継ぐときは、リポジトリを clone したうえで、git 管理外の 3 つを揃えれば同じ state に対して plan / apply / destroy が打てます。

- `terraform/backend.hcl`（上の手順で作る）
- `terraform/terraform.tfvars`（証明書の ARN、AMI ID、Cloudflare のゾーン ID など。元のマシンからコピーする）
- 環境変数 `CLOUDFLARE_API_TOKEN`（次の項）

同じ state に対して 2 か所から同時に apply すると、後から始めたほうがロックの取得で止まります。止まったら先に動いているほうが終わるのを待ちます。

### 受講者向けの手順書を配信する

受講者が読む手順書（`guide/site/index.html`）は S3 + CloudFront で配信します。受講環境とは寿命が違う（手順書は前もって公開して当日まで置いておく）ので、Terraform のルートを `guide/terraform/` に分けてあり、state も同じバケットの別のキーです。

```bash
cd guide/terraform
cp backend.hcl.example backend.hcl        # bucket を受講環境と同じ値にする
terraform init -backend-config=backend.hcl
terraform apply                           # CloudFront の作成に数分かかる
cd ..
./publish.sh                              # site/ を S3 に上げてキャッシュを消す
```

apply の出力 `guide_url` が受講者に配る URL です。中身を直したら `guide/site/` を編集して main に push するだけで、GitHub Actions（`.github/workflows/publish-guide.yml`）が S3 に同期して CloudFront のキャッシュを消します。手で反映したいときは `publish.sh` を打っても同じです。Terraform は触りません。

Actions の認証は OIDC で、GitHub にアクセスキーは置きません。`guide/terraform/terraform.tfvars` に `github_repository`（owner/repo）と、リポジトリと所有者の数値 ID（`gh api repos/<owner>/<repo> --jq .id` と `--jq .owner.id`）を書いて apply すると、このリポジトリの main で動くワークフローだけが assume できるロールができます。数値 ID が要るのは、2026 年 7 月以降に作られたリポジトリでは OIDC トークンの sub に ID が付く形（immutable subject claim）になるためです。apply の出力 `github_actions_role_arn` と `bucket_name`、`distribution_id` を、リポジトリの Settings → Secrets and variables → Actions → Variables に `AWS_ROLE_ARN`、`GUIDE_BUCKET`、`GUIDE_DISTRIBUTION_ID` として登録します（`gh variable set` でもよい）。GitHub の OIDC プロバイダーはアカウントに 1 つあればよく、既にある前提で参照しています。

ワークフローの手動実行（Actions タブの Run workflow）は、ワークフローのファイルが main に入ってからでないと選べません。

独自ドメイン（`guide.handson.example.com` など）を付けるときは、`guide/terraform/terraform.tfvars` に `guide_hostname` と `cloudflare_zone_id` を書いて apply します。CloudFront 用の証明書は us-east-1 で発行する決まりなので、受講環境のワイルドカード証明書（ap-northeast-1）は使えず、Terraform がホスト名単体の証明書を us-east-1 で発行し、検証用の CNAME と本体の CNAME を Cloudflare に入れます。`CLOUDFLARE_API_TOKEN` は受講環境と同じもので構いません。

ハンズオンが終わったら `guide/terraform` で `terraform destroy` すると、バケットの中身ごと消えます。次回も同じ手順書を使うなら残しておいても構いません（費用はほぼゼロ）。

### Cloudflare の API トークンを用意する

`*.handson.example.com` の CNAME を ALB の DNS 名に向けるレコードは、Terraform が Cloudflare のプロバイダー経由で作ります。ALB は `destroy` と `apply` のたびに DNS 名が変わるので、手で差し替える代わりに Terraform に追随させます。

Cloudflare のダッシュボードで API トークンを発行します。「カスタムトークン」を選び、権限は「ゾーン / DNS / 編集」だけ、ゾーンリソースは `base_domain` を管理しているゾーン 1 つだけに絞ります。トークンは tfvars に書かず、`terraform` を実行するシェルの環境変数で渡します。

```bash
export CLOUDFLARE_API_TOKEN=<発行したトークン>
```

ゾーン ID はゾーンの概要ページに表示される値を `terraform.tfvars` の `cloudflare_zone_id` に書きます（秘密ではありません）。

以前に手で入れた `*.handson.example.com` の CNAME が残っている場合は、最初の `apply` の前に Cloudflare 側で削除しておきます。同じ名前の CNAME は 2 本置けないので、残っていると `apply` が失敗します。証明書の検証用 CNAME は Terraform の管理外なので、そのまま残します。

## 2. 当日

### 環境を作る

```bash
terraform plan
terraform apply
```

受講者数は変数で指定します。apply が終わると、受講者ごとの URL とパスワードが出力されます。`*.handson.example.com` の CNAME も同じ apply の中で ALB に向けられます。DNS の反映に数十秒かかるので、URL を開いて確認するのは少し待ってからにします。

ハンズオン当日は `destroy` せず apply したままにしておきます。`destroy` すると CNAME も一緒に消えます。

### 動作確認

配布する前に、主催者が 1 台目の URL を開いて code-server にログインできることを確認します。ALB のターゲットグループがすべて healthy になっているかも見ておきます。

### 受講者に配る

code-server の URL とパスワードに加えて、ハンズオン UI の URL（`participant_ui_urls`）と手順書の URL（`guide/terraform` の `guide_url`）も一緒に配ります。受講者側で必要なのはブラウザだけです。

配ったあとの進行は [curriculum.md](curriculum.md) を参照してください。

### トラブル対応

特定の受講者の環境がおかしくなったときは、Session Manager でその EC2 に入って調べます。

```bash
aws ssm start-session --target <インスタンスID>
```

受講者はこの経路を使いません。主催者の対応用です。

## 3. 後片付け

後片付けは 3 段階です。当日の終了時刻で自動停止が発火し、翌日以降に棚卸しスクリプトで受講者が作ったものを消し、最後に `terraform destroy` で Terraform が作ったものを消します。手順書だけに頼らず、消し忘れても課金が翌日まで伸びないように仕組みで止めます。

これとは別に、受講者には当日の最後に自分の deploy を自分で消してもらいます（`agentcore remove all` のあと `agentcore deploy`。[docs/curriculum.md](curriculum.md) の「5. 振り返る」）。受講者が消す → 消し忘れた分を翌日のスクリプトが拾う、の二段構えです。

### 終了時刻で自動停止する（当日の apply で仕込む）

`terraform.tfvars` に `handson_end_time` を書いて apply すると、その時刻に次の 3 つが起きます。

- 受講者の EC2 のロールに Deny が効き、Bedrock のモデル呼び出しと AgentCore Runtime の呼び出しができなくなる（IAM の `aws:CurrentTime` 条件。追加リソースはなし）
- EventBridge Scheduler が受講者の EC2 を全台停止する
- 同じ時刻に ALB を削除する（ALB は停止できないので削除する）

```hcl
# terraform.tfvars
handson_end_time = "2026-10-31T17:00:00+09:00"   # 秒とオフセットまで書く
handson_timezone = "Asia/Tokyo"                   # 既定値。オフセットと食い違わせない
```

apply の出力 `handson_deadline` に、壁時計の時刻と UTC の両方が出るので、意図した時刻になっているか確認します。

時刻を過ぎたあとの状態と注意点です。

- 止まるのは EC2 と Bedrock の呼び出しで、消えるのは ALB だけです。EBS、AMI のスナップショット、受講者が作った Runtime は残ります。Runtime は呼ばれなければ課金されません
- ALB を Terraform の外で消すので、**時刻を過ぎたあとは `terraform apply` を打たないでください**。apply すると ALB を作り直します。以降は `terraform destroy` の一方向です（destroy は消えたものを refresh で検知するので問題ありません）
- 実行後のスケジュールは自動で消えます（`action_after_completion = DELETE`）。destroy のときに見つからなくても正常です
- 終了時刻を延ばしたいときは、時刻が来る前に `handson_end_time` を書き換えて apply します。すでに過ぎてしまった場合は apply せず、手で `terraform destroy` に進みます
- 検証や試し焼きのときは `handson_end_time` を書かないでおくと、この仕組みは作られません

### 受講者が作ったリソースを消す（翌日以降）

`terraform destroy` で消えるのは Terraform が作ったものだけです。受講者が `agentcore deploy` で作った AgentCore Runtime、その実行ロール、CDK が作った CloudFormation スタック、Runtime のロググループは Terraform の管理外なので残ります。これらは棚卸しスクリプトで消します。

```bash
scripts/cleanup-participant-resources.sh            # 一覧だけ。何も消さない
scripts/cleanup-participant-resources.sh --delete   # 一覧のあと削除する
```

スクリプトは名前が `handson` で始まるものだけを対象にします（`--prefix` で変えられます）。同じアカウントにある別案件の Runtime や EC2 には触りません。

- CloudFormation スタック `AgentCore-handsonuserNN-default` を削除する。Runtime `handsonuserNN_agent` と実行ロールはこの中なので、一緒に消える
- スタックを消したあとに取り残された Runtime と `AgentCore-handson*` のロールがあれば直接消す
- ロググループ `/aws/bedrock-agentcore/runtimes/handson*` を消す（スタックを消しても残る）

ECR は対象外です。deploy は CodeZip 方式で、受講者ごとのリポジトリは作られません。CDK のブートストラップ（`cdk-hnb659fds-*`）は次回も使うので触りません。

削除には受講者数に応じて数分かかります。終わったら一覧モードでもう一度実行し、すべて「なし」になっていることを確認します。

### Terraform で作ったものを消す

```bash
terraform destroy
```

EC2、ALB、ターゲットグループ、セキュリティグループ、VPC、Scheduler と、Cloudflare の `*.handson.example.com` の CNAME が消えます。自動停止で EC2 が停止済み・ALB が削除済みでも、そのまま destroy できます。state は S3 にあるので、apply したマシンでなくても `backend.hcl` と `terraform.tfvars` を揃えれば別のマシンから打てます。`CLOUDFLARE_API_TOKEN` が環境変数に入っていないと CNAME の削除で止まるので、`apply` のときと同じシェルか、トークンを入れ直したシェルで実行します。

### 残ってよいもの

- ACM の証明書（次回も使う。無料）
- Cloudflare の証明書検証用の CNAME（次回も使う。`*.handson.example.com` の CNAME のほうは Terraform が消す）
- AMI とそのスナップショット（次回も使う。EBS スナップショットの保管料がかかる）
- CDK のブートストラップ（次回も使う）
- Terraform の state（S3。次回も同じ場所を使う）

## コスト

単価は ap-northeast-1 のものです（2026-09-05 時点、AWS Price List API で取得）。

| 項目 | 単価 |
|---|---|
| EC2 t4g.small | 0.0216 USD / 時間 |
| EBS gp3 | 0.096 USD / GB・月 |
| ALB | 0.0243 USD / 時間 + 0.008 USD / LCU・時間 |
| AgentCore Runtime | 0.0895 USD / vCPU・時間、0.00945 USD / GB・時間 |
| Nova 2 Lite 入力 | 0.000396 USD / 1K トークン |
| Nova 2 Lite 出力 | 0.003311 USD / 1K トークン |

### 30 人で 5 時間開催した場合

準備 1 時間、ハンズオン 3 時間、片付け 1 時間の想定です。受講者 1 人あたりエージェントを 30 往復動かし、1 往復で入力 2,500 トークン・出力 100 トークンを使うとして計算します。

EC2 は t4g.small の無料トライアル（次の項）が適用される前提です。適用されない場合の金額も右の列に書いています。

| 項目 | 計算 | 金額 | トライアルが無い場合 |
|---|---|---|---|
| EC2 | t4g.small 30 台 × 5 時間 = 150 時間（月 750 時間の枠内） | 0 USD | 3.24 USD |
| EBS | 15GB × 30 台 × 5/730 か月 | 0.31 USD | 0.31 USD |
| ALB | 0.0243 × 5 時間 + LCU | 0.16 USD | 0.16 USD |
| AgentCore Runtime | 1 人 10 分 / 1vCPU / 2GB として 30 人ぶん | 0.54 USD | 0.54 USD |
| Bedrock 入力 | 2,250K トークン | 0.89 USD | 0.89 USD |
| Bedrock 出力 | 90K トークン | 0.30 USD | 0.30 USD |
| **合計** | | **約 2.2 USD** | **約 5.4 USD** |

半日のハンズオンで 2 ドル程度、トライアルが無くても 6 ドル程度です。リハーサルを数回やっても同じ桁に収まります。t4g.medium も試しましたが `agentcore deploy` の所要時間は変わらなかった（small 99 秒、medium 112 秒）ので t4g.small にしています（Issue #15）。

### t4g.small の無料トライアル

t4g.small には AWS の無料トライアルがあります。2021 年に始まって毎年末に延長されてきたもので、2026-09-06 時点の EC2 の FAQ には「2026 年 12 月 31 日まで、すべての AWS のお客様が自動で T4g 無料トライアルに登録される」と書かれています。

| 項目 | 内容 |
|---|---|
| 対象インスタンス | t4g.small のみ（t4g.micro や t4g.medium は対象外） |
| 対象アカウント | 新規・既存を問わずすべて。申し込み不要で自動適用 |
| 無料枠 | 月 750 時間。全リージョンの合算で、同時に何台動かしても稼働時間の合計で数える |
| 対象リージョン | ap-northeast-1（東京）を含む主要リージョン |
| 期限 | 2026 年 12 月 31 日（毎年延長されてきたが、翌年も続く保証はない） |
| Organizations | 支払いアカウント単位で 750 時間。メンバーアカウントごとに 750 時間ではない |
| 無料にならないもの | EBS、ALB、データ転送、CPU クレジットの超過分、AgentCore、Bedrock |

このハンズオンでは 30 台 × 5 時間 = 150 時間なので、リハーサルを 2〜3 回やっても月 750 時間には収まります。同じ月にほかの用途で t4g.small を動かしている場合はその時間も合算されるので、開催月の使用量を確認しておきます。

適用されているかは、開催後に Billing の Cost Explorer で「使用タイプ」を `APN1-BoxUsage:t4g.small` で絞り、料金が 0 になっていることで確認できます。トライアルは CPU クレジットの超過分（Unlimited モードの `CPUSurplus`）を含まないので、そこだけは請求が乗ることがあります。

出典（2026-09-06 取得）。

- Amazon EC2 FAQs の「T4g」の項: https://aws.amazon.com/ec2/faqs/
- 2026 年 1 月分の請求で t4g.small が 0 USD になっていることを CUR で確かめた記事: https://dev.classmethod.jp/en/articles/ec2-t4g-small-free-tier-2026/

### コスト管理で気をつけること

金額そのものより、消し忘れのほうが問題になります。EC2 と ALB は起動している限り課金され続けるので、終わったら `terraform destroy` まで通してください。受講者が作った AgentCore Runtime は Terraform の管理外なので、別途消す必要があります。

Bedrock の利用料は主催者のアカウントに乗ります。アカウントにクレジットが付いていれば、そのまま充当されます。

トークンの実際の使用量は、ハンズオン UI の画面下に出る集計で確認できます。1 往復あたりの入力トークンが想定より多いようなら、この試算も見直してください。
