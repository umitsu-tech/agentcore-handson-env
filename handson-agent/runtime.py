"""AgentCore Runtime にデプロイするときの入口。

ハンズオンの後半で使います。中身は local.py と同じエージェントで、
違うのは「どこで動くか」だけです。

    agentcore deploy

イベントをそのまま yield しているので、呼び出し側には手元で動かしたときと
同じ形のイベントが順に届きます。ハンズオン UI は前半と同じ画面のまま、
実行場所だけが変わった状態を表示できます。
"""

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from agent import build_agent

app = BedrockAgentCoreApp()
agent = build_agent()


@app.entrypoint
async def invoke(payload):
    prompt = payload.get("prompt", "")
    if not prompt:
        yield {"error": "prompt が空です"}
        return

    async for event in agent.stream_async(prompt):
        yield event


if __name__ == "__main__":
    app.run()
