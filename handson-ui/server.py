"""ハンズオン UI。エージェントの動きを画面に流すサーバー。

主催者側の道具です。受講者はこのディレクトリを触りません。

    npm --prefix frontend install
    npm --prefix frontend run build
    uv run uvicorn server:app --host 0.0.0.0 --port 3000 --reload --reload-dir ../handson-agent

code-server の /proxy/3000/ 経由でブラウザから開きます。
画面は frontend/ にある React アプリで、ビルド結果の frontend/dist/ を配信します。

エージェント本体は ../handson-agent にあります。このサーバーはそのディレクトリを
import パスに足して、agent.py と tools.py をそのまま読みます。受講者が tools.py を
書き換えると uvicorn の --reload が拾ってサーバーを再読み込みするので、画面のツール一覧も
次に開いたときには変わっています。場所を変えるときは環境変数 HANDSON_AGENT_DIR で指定します。

この画面はチャット窓ではありません。モデルに何が渡って、モデルが何を返して、
どのツールがどんな引数で呼ばれて、何が返ってきたのかを順に積んでいきます。
ハンズオンで見たいのは「ループの 1 周」だけなので、それ以外は出しません。
"""

import json
import os
import sys
from pathlib import Path

AGENT_DIR = Path(
    os.environ.get("HANDSON_AGENT_DIR") or Path(__file__).resolve().parent.parent / "handson-agent"
)
sys.path.insert(0, str(AGENT_DIR))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import FileResponse, PlainTextResponse  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402
from pydantic import BaseModel  # noqa: E402
from sse_starlette.sse import EventSourceResponse  # noqa: E402

from agent import MODEL_ID, SYSTEM_PROMPT, TOOLS, build_agent  # noqa: E402
from lib.events import to_ui_event  # noqa: E402

app = FastAPI()
DIST_DIR = Path(__file__).parent / "frontend" / "dist"


class AskBody(BaseModel):
    prompt: str


@app.get("/")
def index():
    if not (DIST_DIR / "index.html").exists():
        return PlainTextResponse(
            "画面がまだビルドされていません。frontend/ で npm install と npm run build を実行してください。",
            status_code=503,
        )
    return FileResponse(DIST_DIR / "index.html")


@app.get("/api/context")
def context():
    """モデルに何を渡しているかを画面の最初に出すための情報。

    ツールの説明文（docstring）がそのままモデルに渡っていることを
    受講者に見てもらうのが狙いです。
    """
    return {
        "model_id": MODEL_ID,
        "system_prompt": SYSTEM_PROMPT,
        "tools": [
            {
                "name": tool.tool_spec["name"],
                "description": tool.tool_spec["description"],
                "input_schema": tool.tool_spec["inputSchema"]["json"],
            }
            for tool in TOOLS
        ],
    }


@app.post("/api/ask")
async def ask(body: AskBody):
    agent = build_agent()

    async def stream():
        async for event in agent.stream_async(body.prompt):
            payload = to_ui_event(event)
            if payload is not None:
                yield {"data": json.dumps(payload, ensure_ascii=False)}

    return EventSourceResponse(stream())


# ビルド成果物の配信。ルーティングより後ろに置く必要がある
if (DIST_DIR / "assets").is_dir():
    app.mount("/assets", StaticFiles(directory=DIST_DIR / "assets"), name="assets")
