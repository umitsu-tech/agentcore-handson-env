# ハンズオン用の Strands Agent

社内の備品貸出を案内するエージェントです。備品の在庫や貸出状況は
`data/equipment.json` に入っていて、エージェントはツール経由でそこを読みます。

## ファイル

| ファイル | 役割 |
|---|---|
| `agent.py` | エージェントの定義。モデル、システムプロンプト、使えるツールの一覧 |
| `tools.py` | ツールの中身。ハンズオンではここに関数を足す |
| `local.py` | 手元で動かすときの入口（前半で使う） |
| `runtime.py` | AgentCore Runtime に載せるときの入口（後半で使う） |
| `data/equipment.json` | 備品のデータ |
| `lib/` | 裏方。Strands のイベントを画面に出す形へ変換する `events.py` が入っている。ハンズオンでは触らない |

`local.py` と `runtime.py` はどちらも `agent.py` の `build_agent()` を呼び、
届いたイベントを `lib/events.py` の `to_ui_event()` に通します。同じエージェントを、
動かす場所だけ変えて使う形です。画面に届くイベントの形も同じになります。

ブラウザで動きを見るための画面（ハンズオン UI）は、隣の `../handson-ui/` にあります。
主催者側の道具なので、受講者が中を触る必要はありません。

## 動かす

```bash
uv sync
uv run python local.py
```

聞いてみる例です。

```
> ノートPCの空きある？
> PC-001 って今どうなってる？
```

## ツールを足す

`tools.py` に `@tool` を付けた関数を書いて、`agent.py` の `TOOLS` に足します。

関数の説明文（docstring）はそのままモデルに渡ります。モデルはこの説明を読んで
「今の質問にはこのツールが要る」と判断するので、説明文を変えるとモデルの
選び方も変わります。

ツールは dict や list のデータをそのまま返してください。文章に整形するのは
モデルの仕事です。ツールが返したデータを日本語の文章にして答えるのがモデルの
役割、という分担にしています。

## モデル

`jp.amazon.nova-2-lite-v1:0` を使います。東京リージョンは Nova 2 Lite の
オンデマンド呼び出しに対応していないため、推論プロファイル経由で呼びます。
素の `amazon.nova-2-lite-v1:0` を指定すると失敗します。

環境変数 `MODEL_ID` で差し替えられます。リージョンは `AWS_REGION` を見ますが、
指定がなければ `ap-northeast-1` を使います。Strands は既定で us-east-1 を使うため、
`region_name` を明示的に渡さないと `jp.` から始まる推論プロファイルが弾かれます。

## 手元で動かすときの注意

`aws login` で入れた認証情報をそのまま使うと、botocore が追加の依存を要求して
止まることがあります。その場合は一時的な認証情報を環境変数に展開してから実行してください。

```bash
eval "$(aws configure export-credentials --format env)"
uv run python local.py "ノートPCの空きある？"
```

受講者用の EC2 ではインスタンスプロファイルを使うので、この手順は要りません。

## Runtime へのデプロイ（ハンズオン後半）

```bash
agentcore deploy
```

このコマンドはワークスペース直下（`agentcore/` がある場所。`handson-agent/` の1つ上の階層）で実行します。code-server はワークスペース直下を開いているので、ターミナルを開いた場所がそのまま実行場所になります。

`agentcore/` は agentcore CLI の設定ファイルと CDK のコード一式で、`agentcore create` / `agentcore add agent` で生成したものをそのまま置いています。中身は触らなくて大丈夫です。`agentcore.json` の `runtimes[].name` が Runtime 名になりますが、これは受講者ごとに `handson_user01` のようにインスタンス起動時に自動で置き換わっています（AMI に焼いてある設定はプレースホルダ `handson_PARTICIPANT` のままです）。
