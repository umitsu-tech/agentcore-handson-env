"""AgentCore Runtime にデプロイするときの入口。

ハンズオンの後半で使います。中身は local.py と同じエージェントで、
違うのは「どこで動くか」だけです。

    agentcore deploy

イベントは events.to_ui_event を通してから返します。手元で動かすときも
同じ関数を通すので、呼び出し側にはまったく同じ形のイベントが届きます。
ハンズオン UI は前半と同じ画面のまま、実行場所だけが変わった状態を表示できます。

なお、この変換を省いて Strands のイベントをそのまま返すと、Agent オブジェクトを
含むイベントが JSON にできず、Python の文字列表現のまま届いてしまいます。
"""

from bedrock_agentcore.runtime import BedrockAgentCoreApp

from agent import build_agent
from events import to_ui_event

app = BedrockAgentCoreApp()
agent = build_agent()


@app.entrypoint
async def invoke(payload, context=None):
    prompt = payload.get("prompt", "")
    if not prompt:
        yield {"type": "error", "message": "prompt が空です"}
        return

    async for event in agent.stream_async(prompt):
        ui_event = to_ui_event(event)
        if ui_event is not None:
            yield ui_event
