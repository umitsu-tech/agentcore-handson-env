# ハンズオン UI

エージェントの動きをブラウザで見せるための画面とサーバーです。主催者側の道具で、
受講者はこのディレクトリを触りません。エージェント本体は `../handson-agent/` にあります。

## ファイル

| ファイル | 役割 |
|---|---|
| `server.py` | FastAPI のサーバー。API と画面の配信 |
| `frontend/` | 画面（React + Vite）。ビルド結果の `frontend/dist/` を `server.py` が配信する |

## 動かす

画面は React で書いてあるので、先にビルドします。

```bash
uv sync
npm --prefix frontend install
npm --prefix frontend run build
uv run uvicorn server:app --host 0.0.0.0 --port 3000 --reload --reload-dir ../handson-agent
```

code-server の `/proxy/3000/` から開きます。

`server.py` は `../handson-agent` を import パスに足して、`agent.py` と `tools.py` をそのまま読みます。
`--reload --reload-dir ../handson-agent` を付けておくと、受講者が `tools.py` を保存したときに
サーバーが再読み込みされ、画面のツール一覧も次に開いたときには変わっています。
エージェントの場所を変えるときは環境変数 `HANDSON_AGENT_DIR` で指定します。

画面を触りながら開発するときは、別のターミナルで Vite の開発サーバーを立てると
保存のたびに反映されます。API は 3000 番のサーバーに転送されます。

```bash
npm --prefix frontend run dev
```

## 画面が出すもの

チャット窓ではありません。1 回のやりとりで、モデルが何を受け取り、どのツールをどんな引数で呼び、
何が返ってきて、最終的にどう答えたのかを上から順に積んでいきます。

- 画面上部の折りたたみに、システムプロンプトとツールの一覧（`tools.py` の docstring がそのまま出る）
- ループの流れ（質問 → ツール呼び出し → 結果 → 答え）
- 生のイベントの折りたたみ
- 1 回のやりとりの集計（ループの周回数、トークン数、停止理由、ツール呼び出し回数）

## Runtime の呼び出し

`agentcore deploy` で AgentCore Runtime にエージェントをデプロイすると、画面に
「手元で動かす / Runtime で動かす」の切り替えが増えます。未デプロイのときは
`GET /api/runtime` が `available: false` を返し、切り替え自体を出しません
（受講者ごとに見える画面が変わります）。

Runtime の特定は次の順で行います。

1. 環境変数 `HANDSON_RUNTIME_ARN` があればそれをそのまま使う
2. 無ければ `agentcore/.cli/deployed-state.json`（`agentcore deploy` が書く）の `targets.default.resources.runtimes` から ARN を読む。`agentcore/` の場所は既定で `HANDSON_AGENT_DIR` の1つ上だが、環境変数 `HANDSON_AGENTCORE_DIR` で上書きできる
3. それも無ければ `agentcore/agentcore.json` のプロジェクト名と runtime 名から実名（`<プロジェクト名>_<runtime 名>`、例 `handsonuser01_agent`）を組み立て、`ListAgentRuntimes` で探す

見つかった結果だけをプロセス内でキャッシュします。未デプロイ→デプロイ済みへの変化は、
画面をリロードすれば拾えます（キャッシュは「見つかったとき」だけ効くため）。

`POST /api/ask` は `target: "local" | "runtime"` を受け取ります。`"runtime"` のときは
`InvokeAgentRuntime` をストリーミングで呼び、`runtimeSessionId` はリクエストごとに新しい UUID
にします。手元の `/api/ask` がリクエストごとに `build_agent()` を作り直して会話をリセットするのと
同じ挙動にするためです。認証情報が無い・権限が無い・Runtime が見つからないなどの失敗は、
画面が「network error」だけで止まらないよう `{"type": "error", "message": ...}` のイベントとして流します。
