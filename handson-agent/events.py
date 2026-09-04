"""Strands のイベントを、画面に出すぶんだけに絞って変換する。

手元で動かすとき（ui.py）も、AgentCore Runtime に載せたとき（runtime.py）も、
画面に届くのはこの関数を通したイベントです。両方で同じ関数を使うので、
実行される場所が変わっても画面の見え方は変わりません。

Runtime 経由で返すときは、この変換が必須です。Strands のイベントには
Agent オブジェクトそのものが入っていて、そのまま返そうとすると JSON に
できず、Python の文字列表現のまま届いてしまいます。
"""


def to_ui_event(event: dict) -> dict | None:
    """1 つのイベントを、画面に出す形に変換する。出さないものは None を返す。

    Strands は生成の途中経過を細かくイベントで返します。全部出すと情報が
    多すぎて何が起きているか分からなくなるので、ループの流れが見える
    最低限だけを通します。
    """
    if event.get("init_event_loop"):
        return {"type": "loop_start"}

    # モデルが「このツールを呼べ」と言っている状態。引数は少しずつ届くので、
    # 同じ toolUseId のイベントが何度も来ます。画面側で同じカードを更新します。
    if "current_tool_use" in event:
        use = event["current_tool_use"]
        if use.get("name"):
            return {
                "type": "tool_use",
                "id": use.get("toolUseId"),
                "name": use["name"],
                "input": use.get("input"),
            }

    # ツールの実行結果は、user ロールのメッセージとして戻ってきます
    if "message" in event:
        message = event["message"]
        results = [
            block["toolResult"]
            for block in message.get("content", [])
            if isinstance(block, dict) and "toolResult" in block
        ]
        if results:
            return {
                "type": "tool_result",
                "results": [
                    {
                        "id": result.get("toolUseId"),
                        "status": result.get("status"),
                        "text": "\n".join(
                            content.get("text", "")
                            for content in result.get("content", [])
                            if isinstance(content, dict)
                        ),
                    }
                    for result in results
                ],
            }

    if "data" in event:
        return {"type": "text", "text": event["data"]}

    if "result" in event:
        return {"type": "done"}

    return None
