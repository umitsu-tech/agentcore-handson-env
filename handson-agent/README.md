# ハンズオン用の Strands Agent

社内の備品貸出を案内するエージェントです。備品の在庫や貸出状況は
`data/equipment.json` に入っていて、エージェントはツール経由でそこを読みます。

## ファイル

| ファイル | 役割 |
|---|---|
| `agent.py` | エージェントの定義。モデル、システムプロンプト、使えるツールの一覧 |
| `tools.py` | ツールの中身。ハンズオンではここに関数を足す |
| `events.py` | Strands のイベントを画面に出す形へ変換する。手元でも Runtime でも共通 |
| `ui.py` | ハンズオン UI のサーバー。エージェントの動きを画面に流す |
| `static/index.html` | ハンズオン UI の画面 |
| `local.py` | 手元で動かすときの入口（前半で使う） |
| `runtime.py` | AgentCore Runtime に載せるときの入口（後半で使う） |
| `data/equipment.json` | 備品のデータ |

`local.py` と `runtime.py` はどちらも `agent.py` の `build_agent()` を呼び、
届いたイベントを `events.py` の `to_ui_event()` に通します。同じエージェントを、
動かす場所だけ変えて使う形です。画面に届くイベントの形も同じになります。

## 動かす

```bash
uv sync
uv run python local.py
```

ブラウザで見るときはこちらです。

```bash
uv run uvicorn ui:app --host 0.0.0.0 --port 3000
```

code-server の `/proxy/3000/` から開きます。

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
