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

受講者用の EC2 を 1 台起動して、次のものをセットアップします。

- code-server（8080 番で待ち受け）
- ハンズオン UI（3000 番。エージェントの動きを可視化する画面）
- Strands Agent の雛形プロジェクト
- Node.js、Python、uv、AWS CLI、AWS CDK、AgentCore CLI（`npm install -g @aws/agentcore`）

セットアップが終わったら通しで動作確認をします。code-server にブラウザから入れること、`agentcore deploy` が最後まで通ること、デプロイしたエージェントをハンズオン UI から呼んで動きが画面に出ることの 3 点を確認してから AMI を作成します。

AMI の ID は Terraform の変数に渡します。

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

## コストの考え方

主な課金要素は次の 3 つです。

- EC2（受講者数 × 起動していた時間）
- ALB（稼働していた時間 + 処理量）
- AgentCore Runtime（受講者が動かした時間ぶん。CPU とメモリの実使用量に応じた従量課金）

いずれも起動時間ぶんの課金なので、当日の朝に作って終了後に消せば短時間ぶんで収まります。作りっぱなしにすると EC2 と ALB が動き続けるため、片付けを忘れないことが一番のコスト対策です。

実際の金額は、受講者数とリハーサル回数が決まってから試算します。
