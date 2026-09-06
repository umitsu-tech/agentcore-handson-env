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

import asyncio
import json
import os
import queue
import sys
import threading
import uuid
from pathlib import Path
from typing import Literal

AGENT_DIR = Path(
    os.environ.get("HANDSON_AGENT_DIR") or Path(__file__).resolve().parent.parent / "handson-agent"
)
sys.path.insert(0, str(AGENT_DIR))

import boto3  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.responses import FileResponse, PlainTextResponse  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402
from pydantic import BaseModel  # noqa: E402
from sse_starlette.sse import EventSourceResponse  # noqa: E402

from agent import MODEL_ID, SYSTEM_PROMPT, TOOLS, build_agent  # noqa: E402
from lib.events import to_ui_event  # noqa: E402

app = FastAPI()
DIST_DIR = Path(__file__).parent / "frontend" / "dist"

# list_agent_runtimes で見つかったときだけ埋める。未デプロイ→デプロイ済みへの変化は
# 画面のリロードで拾えるように、「見つからなかった」結果はキャッシュしない。
_runtime_cache: dict | None = None


class AskBody(BaseModel):
    prompt: str
    target: Literal["local", "runtime"] = "local"


def _agentcore_dir() -> Path:
    """agentcore CLI の設定ディレクトリ（agentcore.json・.cli/ がある場所）。

    既定は AGENT_DIR（handson-agent/）の 1 つ上の agentcore/。環境変数
    HANDSON_AGENTCORE_DIR で上書きできる（配置替えやテストのため）。
    """
    override = os.environ.get("HANDSON_AGENTCORE_DIR")
    return Path(override) if override else AGENT_DIR.parent / "agentcore"


def _read_agentcore_config(agentcore_dir: Path) -> tuple[str, str] | None:
    """agentcore.json からプロジェクト名と runtime 名を読む。

    Bedrock 側の Runtime の実名は `<プロジェクト名>_<runtime 名>` になる。
    """
    try:
        config = json.loads((agentcore_dir / "agentcore.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    project = config.get("name")
    runtimes = config.get("runtimes") or []
    if not project or not runtimes:
        return None
    runtime_name = runtimes[0].get("name")
    if not runtime_name:
        return None
    return project, runtime_name


def _read_deployed_state_arn(agentcore_dir: Path, runtime_name: str | None) -> str | None:
    """`agentcore deploy` が書く .cli/deployed-state.json から Runtime の ARN を読む。

    targets.default.resources.runtimes は agentcore.json の runtime 名をキーにした
    辞書。設定と同じ runtime 名があればそれを使い、無ければ最初の 1 件を使う。
    """
    try:
        state = json.loads((agentcore_dir / ".cli" / "deployed-state.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    runtimes = state.get("targets", {}).get("default", {}).get("resources", {}).get("runtimes", {})
    if not runtimes:
        return None
    if runtime_name and runtime_name in runtimes:
        return runtimes[runtime_name].get("runtimeArn")
    return next(iter(runtimes.values()), {}).get("runtimeArn")


def resolve_runtime() -> dict:
    """デプロイ済みの Runtime を探す。ブロッキングする（boto3 呼び出し）ので、
    呼び出し側で asyncio.to_thread に包むか、同期のパスオペレーション内で呼ぶこと。

    探す順序は次のとおり。
    1. 環境変数 HANDSON_RUNTIME_ARN があればそれをそのまま使う
    2. agentcore/.cli/deployed-state.json に書かれた ARN を使う（agentcore deploy 直後はこれで見つかる）
    3. agentcore.json のプロジェクト名と runtime 名から実名を組み立て、ListAgentRuntimes で探す
    """
    global _runtime_cache
    if _runtime_cache is not None:
        return _runtime_cache

    region = os.environ.get("AWS_REGION", "ap-northeast-1")
    agentcore_dir = _agentcore_dir()
    config = _read_agentcore_config(agentcore_dir)
    project, runtime_name = config if config else (None, None)
    name = f"{project}_{runtime_name}" if project and runtime_name else ""

    env_arn = os.environ.get("HANDSON_RUNTIME_ARN")
    if env_arn:
        result = {"available": True, "name": name, "arn": env_arn, "region": region}
        _runtime_cache = result
        return result

    state_arn = _read_deployed_state_arn(agentcore_dir, runtime_name)
    if state_arn:
        result = {"available": True, "name": name, "arn": state_arn, "region": region}
        _runtime_cache = result
        return result

    if not project or not runtime_name:
        return {
            "available": False,
            "name": name,
            "arn": None,
            "region": region,
            "reason": f"{agentcore_dir}/agentcore.json からプロジェクト名や runtime 名を読めません",
        }

    try:
        client = boto3.client("bedrock-agentcore-control", region_name=region)
        next_token = None
        while True:
            kwargs = {"maxResults": 100}
            if next_token:
                kwargs["nextToken"] = next_token
            resp = client.list_agent_runtimes(**kwargs)
            for runtime in resp.get("agentRuntimes", []):
                if runtime.get("agentRuntimeName") == name:
                    result = {
                        "available": True,
                        "name": name,
                        "arn": runtime["agentRuntimeArn"],
                        "region": region,
                    }
                    _runtime_cache = result
                    return result
            next_token = resp.get("nextToken")
            if not next_token:
                break
        return {
            "available": False,
            "name": name,
            "arn": None,
            "region": region,
            "reason": "Runtime が見つかりません（agentcore deploy が未実行の可能性）",
        }
    except Exception as e:  # noqa: BLE001 — 認証情報なし・権限不足などなんであれ available: false にする
        return {"available": False, "name": name, "arn": None, "region": region, "reason": str(e)}


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


@app.get("/api/runtime")
def runtime():
    """Runtime にデプロイ済みかどうか。画面はこれを見て切り替えの有無を決める。"""
    return resolve_runtime()


async def _stream_local(prompt: str):
    agent = build_agent()
    async for event in agent.stream_async(prompt):
        payload = to_ui_event(event)
        if payload is not None:
            yield {"data": json.dumps(payload, ensure_ascii=False)}


def _invoke_runtime_worker(prompt: str, info: dict, out: "queue.Queue[dict | object]", sentinel: object):
    """別スレッドで invoke_agent_runtime を呼び、届いた行を1つずつキューへ積む。

    boto3 はブロッキング呼び出しなので、async ジェネレータの中で直接 await できない。
    スレッドに逃がしてキュー経由で読み出す。
    """
    try:
        client = boto3.client("bedrock-agentcore", region_name=info["region"])
        # 手元の /api/ask はリクエストごとに build_agent() を作り直すので会話がリセットされる。
        # Runtime 側でも同じ挙動にするため、runtimeSessionId は毎回新規の UUID にする。
        response = client.invoke_agent_runtime(
            agentRuntimeArn=info["arn"],
            runtimeSessionId=str(uuid.uuid4()),
            contentType="application/json",
            accept="text/event-stream",
            payload=json.dumps({"prompt": prompt}).encode("utf-8"),
        )
        body = response["response"]
        for line in body.iter_lines(chunk_size=10):
            if not line:
                continue
            text = line.decode("utf-8") if isinstance(line, bytes) else line
            if not text.startswith("data:"):
                continue
            data = text[len("data:"):].strip()
            if not data:
                continue
            try:
                payload = json.loads(data)
            except json.JSONDecodeError:
                continue
            out.put(payload)
    except Exception as e:  # noqa: BLE001 — 画面が「network error」だけになるのを避ける
        out.put({"type": "error", "message": str(e)})
    finally:
        out.put(sentinel)


async def _stream_runtime(prompt: str):
    info = await asyncio.to_thread(resolve_runtime)
    if not info.get("available") or not info.get("arn"):
        yield {
            "data": json.dumps(
                {"type": "error", "message": "Runtime が見つかりません。デプロイ済みか確認してください。"},
                ensure_ascii=False,
            )
        }
        return

    q: "queue.Queue[dict | object]" = queue.Queue()
    sentinel = object()
    thread = threading.Thread(target=_invoke_runtime_worker, args=(prompt, info, q, sentinel), daemon=True)
    thread.start()

    while True:
        item = await asyncio.to_thread(q.get)
        if item is sentinel:
            break
        yield {"data": json.dumps(item, ensure_ascii=False)}


@app.post("/api/ask")
async def ask(body: AskBody):
    stream = _stream_runtime(body.prompt) if body.target == "runtime" else _stream_local(body.prompt)
    return EventSourceResponse(stream)


# ビルド成果物の配信。ルーティングより後ろに置く必要がある
if (DIST_DIR / "assets").is_dir():
    app.mount("/assets", StaticFiles(directory=DIST_DIR / "assets"), name="assets")
