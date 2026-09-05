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
aws login
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

### DNS のレコードを引く

ALB を作ったあと、`*.handson.example.com` の CNAME を ALB の DNS 名に向けて Cloudflare に追加します。プロキシは無効（DNS only）にします。

このレコードはハンズオンが終わっても残して構いません。向き先の ALB が消えると名前解決の結果が返らなくなるだけです。

## 2. 当日

### 環境を作る

```bash
terraform plan
terraform apply
```

受講者数は変数で指定します。apply が終わると、受講者ごとの URL とパスワードが出力されます。

### 動作確認

配布する前に、主催者が 1 台目の URL を開いて code-server にログインできることを確認します。ALB のターゲットグループがすべて healthy になっているかも見ておきます。

### 受講者に配る

URL とパスワードを配布します。受講者側で必要なのはブラウザだけです。

配ったあとの進行は [curriculum.md](curriculum.md) を参照してください。

### トラブル対応

特定の受講者の環境がおかしくなったときは、Session Manager でその EC2 に入って調べます。

```bash
aws ssm start-session --target <インスタンスID>
```

受講者はこの経路を使いません。主催者の対応用です。

## 3. 後片付け

### 受講者が作ったリソースを消す

`terraform destroy` で消えるのは Terraform が作ったものだけです。受講者が `agentcore deploy` で作った AgentCore Runtime、その実行ロール、CDK が作った CloudFormation スタックは Terraform の管理外なので残ります。

これらを先に片付けます。残っている AgentCore Runtime は課金対象になり得るので、消し忘れないようにします。

- AgentCore Runtime の一覧を確認して削除する
- CDK が作った CloudFormation スタックを削除する
- `*BedrockAgentCore*` のロールが残っていないか確認する

### Terraform で作ったものを消す

```bash
terraform destroy
```

EC2、ALB、ターゲットグループ、セキュリティグループ、VPC が消えます。

### 残ってよいもの

- ACM の証明書（次回も使う。無料）
- Cloudflare の DNS レコード（次回も使う）
- AMI とそのスナップショット（次回も使う。EBS スナップショットの保管料がかかる）
- CDK のブートストラップ（次回も使う）

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

| 項目 | 計算 | 金額 |
|---|---|---|
| EC2 | 0.0216 × 30 台 × 5 時間 | 3.24 USD |
| EBS | 30GB × 30 台 × 5/730 か月 | 0.59 USD |
| ALB | 0.0243 × 5 時間 + LCU | 0.16 USD |
| AgentCore Runtime | 1 人 10 分 / 1vCPU / 2GB として 30 人ぶん | 0.54 USD |
| Bedrock 入力 | 2,250K トークン | 0.89 USD |
| Bedrock 出力 | 90K トークン | 0.30 USD |
| **合計** | | **約 5.7 USD** |

半日のハンズオンで 6 ドル程度です。リハーサルを数回やっても同じ桁に収まります。

### コスト管理で気をつけること

金額そのものより、消し忘れのほうが問題になります。EC2 と ALB は起動している限り課金され続けるので、終わったら `terraform destroy` まで通してください。受講者が作った AgentCore Runtime は Terraform の管理外なので、別途消す必要があります。

Bedrock の利用料は主催者のアカウントに乗ります。アカウントにクレジットが付いていれば、そのまま充当されます。

トークンの実際の使用量は、ハンズオン UI の画面下に出る集計で確認できます。1 往復あたりの入力トークンが想定より多いようなら、この試算も見直してください。
