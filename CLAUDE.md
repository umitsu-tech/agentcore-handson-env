# AgentCore ハンズオン環境 — 作業メモ

Amazon Bedrock AgentCore のハンズオン環境を Terraform で構築するプロジェクトです。プロジェクトの概要は [README.md](README.md)、構成の詳細は [docs/architecture.md](docs/architecture.md)、運用手順は [docs/operations.md](docs/operations.md) を参照してください。

## 現在の状況

最終更新: 2026-09-05

### 決まっていること

- 受講者は 10〜30 人。主催者の AWS アカウント 1 つに全員が入る
- 受講者に AWS の認証情報は配らない。EC2 のインスタンスプロファイルで `agentcore deploy` まで通す
- 入口は ALB + HTTPS。ホスト名（`userNN.handson.<ドメイン>`）で受講者ごとの EC2 に振り分ける
- DNS は Cloudflare。ワイルドカードの CNAME を ALB に向ける（プロキシは無効）
- EC2 は t4g.small / Amazon Linux 2023 / ARM64。1 人 1 台
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

### できているもの

いずれもレビュー待ちの PR に乗っている段階で、main にはまだ入っていない。

- 構成図とドキュメント（README.md、docs/architecture.md、docs/curriculum.md、docs/operations.md）
- Strands Agent の雛形（`handson-agent/`）。実機で Nova 2 Lite がツールを正しく選ぶところまで確認した
- ハンズオン UI（`handson-agent/frontend/`、React + Vite）。生のイベント、トークン数、ループの周回数を出す
- 1 人分の Terraform（`terraform/`）。`terraform plan` が 26 リソースで通るところまで
- 受講環境のセットアップスクリプト（`scripts/setup-instance.sh`）と、それを焼いた AMI（`ami-0212faf4372e1a817` / arm64）
- コストの試算。30 人 5 時間で約 5.7 USD（内訳は docs/operations.md）

### 次の一歩

まずレビューとマージ。PR が 5 本あり、依存関係があるので順番が決まっている。#11 → #13 → #14 → #16 → #12 の順で、#14 は #13 宛、#16 は #14 宛なので、それぞれマージしたあとに base を main へ付け替える。

そのあとが AMI からの通し確認（Issue #5 の残り）。1 台起動して、ブラウザから code-server に入れること、`agentcore deploy` が通ること、デプロイしたエージェントをハンズオン UI から呼べることを確認する。あわせて Issue #15 のスペック実測（code-server で TypeScript を開いた状態と `agentcore deploy` 中のメモリ）も同じ 1 台で取る。

その結果を Terraform へ反映する。いまの `terraform/` は user_data で全部セットアップする形のままなので、`ami_id` に AMI を渡し、user_data は code-server のパスワード設定だけに縮める。

そこまで済んだら、人数ぶんへの展開（#6）、事前準備（#7）、リハーサル（#8）と進む。

### 未確定

- EBS のサイズとインスタンスタイプ。実測はディスク 4.3GB / メモリ 468MB で、30GB と t4g.small は余っている。15GB と t4g.micro が候補（Issue #15）
- ALB に付ける ACM のワイルドカード証明書と、Cloudflare のレコード。どちらも未作成で `terraform apply` はこれ待ち
- 本番でモデル制限をどうかけるか（検証の段階ではかけない方針）

## 作業のルール

- 作業の区切りごとに、この「現在の状況」を更新してコミットする。別の場所でセッションを再開しても状況が分かるようにするため
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
