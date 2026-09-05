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
- 教材（受講者の EC2 に置くファイル一式）は `handson-agent/`（受講者が触る雛形）と `handson-ui/`（主催者側の UI）に分ける。受講者が code-server を開いたときに、触るファイルだけが平置きで見える形にする。裏方の `events.py` は `handson-agent/lib/` に寄せる
- ツールはデータ（dict / list）を返し、日本語にするのはモデルの仕事にする。ツールの結果とモデルの答えが同じ文になると、モデルが何を足したのか見えないため
- ハンズオン UI の見せ方は、ループの 1 周を「モデルを呼んで、ツールを実行して、結果を受け取るまで」とし、周ごとに折りたためる見出しで区切る。色は 3 つだけで、青緑はループの入口と出口（お題の質問と最終的な答え）、青はモデルに入るもの、オレンジはモデルかツールから出てくるもの。周の境目では同じカードを重複して出し、色をオレンジから青に切り替えて「出てきたものを次は入れる」を見せる
- UI は常にライトテーマ、端末のフォントだけを使い、本文 16px・補助 13px 以上、白地でコントラスト比 4.5 以上を保つ（プロジェクターで見にくかったため）
- UI のサーバーは `uvicorn --reload --reload-dir ../handson-agent` で起動し、受講者が `tools.py` を保存したら画面のツール一覧が追随するようにする
- 後片付けは仕組みで担保する（Issue #17）。ハンズオン由来のリソースだけを選んで消す棚卸しスクリプトを本命に、終了時刻を Terraform の変数で渡して IAM の Deny・EC2 停止・ALB 削除を時刻で発火させる。Budgets は既存のものを使う
- モデルは比較のうえ Nova 2 Lite に据え置く。Nova Micro や旧 Nova Lite は安いが世代が古く、オープンモデルは Converse API でのツール呼び出しが未確認。下がる幅も最大 1 USD 程度で、ツール選択の確実さを優先した

### できているもの

すべて main にマージ済み（2026-09-05）。

- 構成図とドキュメント（README.md、docs/architecture.md、docs/curriculum.md、docs/operations.md）
- Strands Agent の雛形（`handson-agent/`）。実機でモデル呼び出し、Nova 2 Lite のツール選択、Runtime へのデプロイまで確認した。ツールはデータ（dict / list）を返す
- ハンズオン UI（`handson-ui/`、React + Vite + FastAPI）。周ごとの見出しと折りたたみ、入力と出力の 2 色、ツールの結果の JSON 表示、Markdown 記号の抑制、ラベルの補足まで入っている
- 受講環境のセットアップスクリプト（`scripts/setup-instance.sh`）。`handson-ui/` 分離後の構成に追随済み
- 1 人分の Terraform（`terraform/`）。AMI 前提の構成で、`ami_id` を必須で受け取り、user_data は code-server のパスワードを差し込むだけ。`terraform plan` が 26 リソースで通るところまで（apply は証明書と DNS 待ち）
- コストの試算。30 人 5 時間で約 5.7 USD（内訳は docs/operations.md）
- 東京リージョンで使えるモデルの単価比較（結論は Nova 2 Lite 据え置き）

まだ手が要るもの。

- AMI `ami-0212faf4372e1a817`（arm64）は `handson-ui/` 分離前のスクリプトで焼いたもの。教材を `handson-workspace.tar.gz` として S3 に上げ直してから焼き直す

### 次の一歩

PR はすべてマージ済みなので、ここからは PC の前で行う作業になる（リモートの作業環境からは AWS の変更操作が通らない）。

1. 教材（`handson-agent/` と `handson-ui/`）を `handson-workspace.tar.gz` にして S3 に上げ直す
2. `scripts/setup-instance.sh` で AMI を焼き直す。このときルートボリュームを Issue #15 の結論のサイズにする
3. ACM のワイルドカード証明書と Cloudflare のレコードを用意する
4. `terraform apply` で 1 台立てて通し確認をする。ブラウザから code-server に入れること、`tools.py` を保存すると画面のツール一覧が追随すること、`agentcore deploy` が通ること、デプロイしたエージェントをハンズオン UI から呼べること。あわせて Issue #15 の未測定分（code-server で TypeScript を開いた状態と `agentcore deploy` 中のメモリ）を取る。ここまでで Issue #2、#5、#15 を閉じる
5. 後片付けの仕組み（Issue #17）を実装する
6. 人数ぶんへの展開（Issue #6）

当日の運営（事前準備、リハーサル）はこのリポジトリの範囲外にした（Issue #7、#8 はクローズ）。

### 未確定

- EBS のサイズとインスタンスタイプ。実測はディスク 4.3GB / メモリ 468MB で、30GB と t4g.small は余っている。15GB と t4g.micro が候補（Issue #15）。`agentcore deploy` 中のメモリは未測定
- ALB に付ける ACM のワイルドカード証明書と、Cloudflare のレコード。どちらも未作成で `terraform apply` はこれ待ち
- 本番でモデル制限をどうかけるか（検証の段階ではかけない方針）
- UI のサーバー側で Bedrock の呼び出しが失敗したとき、画面には「network error」としか出ない。例外を捕まえてエラーの内容を流す改善を別 Issue にする予定
- UI のサーバーを本番でも `--reload` 付きで動かすか。1 人 1 台なので負荷は問題ないが、保存すると再起動する挙動を受講者に説明する必要がある

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
