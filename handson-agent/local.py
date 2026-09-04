"""手元でエージェントを動かす入口。

ハンズオンの前半で使います。ターミナルから対話するとエージェントの動きが
そのまま流れるので、まずはここでループの仕組みを掴みます。

    uv run python local.py

ハンズオン UI（3000 番）からもこのエージェントを呼びます。
"""

import asyncio
import sys

from agent import build_agent


async def ask(agent, prompt: str) -> None:
    """1 回のやりとりを実行して、届いたイベントを流す。

    stream_async はモデルの応答やツールの呼び出しをイベントとして順に返します。
    ハンズオン UI は、このイベントを受け取って画面に表示します。
    """
    async for event in agent.stream_async(prompt):
        if "data" in event:
            print(event["data"], end="", flush=True)
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
