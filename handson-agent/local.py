"""手元でエージェントを動かす入口。

ハンズオンの前半で使います。ターミナルから対話するとエージェントの動きが
そのまま流れるので、まずはここでループの仕組みを掴みます。

    uv run python local.py

ハンズオン UI（3000 番）からもこのエージェントを呼びます。
"""

import asyncio
import sys

from agent import build_agent
from events import to_ui_event


async def ask(agent, prompt: str) -> None:
    """1 回のやりとりを実行して、届いたイベントを流す。

    stream_async はモデルの応答やツールの呼び出しをイベントとして順に返します。
    ここでは events.to_ui_event を通した結果を素朴に表示しています。
    ハンズオン UI（ui.py）も Runtime（runtime.py）も同じ関数を使うので、
    どこで動かしても届くイベントの形は同じです。
    """
    async for event in agent.stream_async(prompt):
        ui_event = to_ui_event(event)
        if ui_event is None:
            continue

        if ui_event["type"] == "text":
            print(ui_event["text"], end="", flush=True)
        elif ui_event["type"] == "tool_use":
            print(f"\n[ツールを呼びます] {ui_event['name']} {ui_event.get('input') or ''}", flush=True)
        elif ui_event["type"] == "tool_result":
            for result in ui_event["results"]:
                print(f"[ツールの結果] {result['text']}", flush=True)
    print()


async def main() -> None:
    agent = build_agent()

    if len(sys.argv) > 1:
        await ask(agent, " ".join(sys.argv[1:]))
        return

    print("備品について聞いてみてください（Ctrl-C で終了）")
    while True:
        try:
            prompt = input("\n> ")
        except (EOFError, KeyboardInterrupt):
            print()
            return

        if prompt.strip():
            await ask(agent, prompt)


if __name__ == "__main__":
    asyncio.run(main())
