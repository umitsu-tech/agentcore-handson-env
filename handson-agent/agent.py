"""エージェントの本体。

手元で動かすとき（local.py）も、AgentCore Runtime に載せたとき（runtime.py）も、
呼ばれるのはこの build_agent() です。同じエージェントが動く場所だけを変える、
というのがこのハンズオンの後半のポイントになります。
"""

import os

from strands import Agent
from strands.models import BedrockModel

import tools

# 東京リージョンは Nova 2 Lite のオンデマンド呼び出しに対応していないため、
# 推論プロファイル（jp. から始まる ID）を指定します。
# 素の "amazon.nova-2-lite-v1:0" を指定すると呼び出しに失敗します。
MODEL_ID = os.environ.get("MODEL_ID", "jp.amazon.nova-2-lite-v1:0")

# リージョンは明示的に渡します。指定しないと Strands は us-east-1 を既定にするため、
# jp. から始まる推論プロファイルが「モデル ID が不正」として弾かれます。
REGION = os.environ.get("AWS_REGION", "ap-northeast-1")

SYSTEM_PROMPT = """あなたは社内の備品貸出を案内するアシスタントです。

備品の在庫や貸出状況は、必ずツールで調べてから答えてください。
ツールを使わずに推測で答えてはいけません。

答えるときは日本語で、短く具体的に伝えてください。
"""

# モデルに渡すツールの一覧。ここに並べたものだけがモデルから見えます。
TOOLS = [
    tools.search_equipment,
    tools.get_equipment_status,
]


def build_agent() -> Agent:
    model = BedrockModel(
        model_id=MODEL_ID,
        region_name=REGION,
        temperature=0.3,
    )

    return Agent(
        model=model,
        tools=TOOLS,
        system_prompt=SYSTEM_PROMPT,
        # 既定のハンドラは標準出力に応答を書き出します。こちらでもイベントを
        # 受け取って表示するので、そのままだと同じ文字が二重に出ます。
        callback_handler=None,
    )
