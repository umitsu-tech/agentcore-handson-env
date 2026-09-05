"""Strands のイベントを、画面に出す形へ変換する。

手元で動かすとき（ui.py）も、AgentCore Runtime に載せたとき（runtime.py）も、
画面に届くのはこの関数を通したイベントです。両方で同じ関数を使うので、
実行される場所が変わっても画面の見え方は変わりません。

Runtime 経由で返すときは、この変換が必須です。Strands のイベントには
Agent オブジェクトそのものが入っていて、そのまま返そうとすると JSON に
できず、Python の文字列表現のまま届いてしまいます。
"""

import json

# JSON にできない、あるいは出しても読めないキー。生データからは外します。
_SKIP_KEYS = {
    "agent",
    "callback_handler",
    "event_loop_cycle_id",
    "event_loop_cycle_span",
    "event_loop_parent_span",
    "event_loop_parent_cycle_id",
    "event_loop_cycle_trace",
    "request_state",
    "result",
}


def _serializable(event: dict) -> dict:
    """イベントから、そのまま JSON にできる部分だけを取り出す。"""
    out: dict = {}
    for key, value in event.items():
        if key in _SKIP_KEYS:
            continue
        try:
            json.dumps(value, ensure_ascii=False)
        except (TypeError, ValueError):
            value = repr(value)
        out[key] = value
    return out


def _summarize_result(result) -> dict:
    """最後に届く AgentResult から、画面に出したいものを取り出す。

    トークン数が見えると、この回答にいくら掛かったのかという話につなげられます。
    """
    summary: dict = {"stop_reason": str(getattr(result, "stop_reason", ""))}

    metrics = getattr(result, "metrics", None)
    if metrics is None:
        return summary

    usage = getattr(metrics, "accumulated_usage", None)
    if usage:
        summary["usage"] = dict(usage)

    cycle_count = getattr(metrics, "cycle_count", None)
    if cycle_count is not None:
        # ループを何周したか。ツールを呼ぶと 2 周以上になります
        summary["cycles"] = cycle_count

    tool_metrics = getattr(metrics, "tool_metrics", None)
    if tool_metrics:
        tools = {}
        for name, metric in tool_metrics.items():
            entry = {}
            for attribute in ("call_count", "success_count", "error_count", "total_time"):
                value = getattr(metric, attribute, None)
                if value is not None:
                    entry[attribute] = round(value, 3) if isinstance(value, float) else value
            tools[name] = entry
        summary["tools"] = tools

    return summary


def to_ui_event(event: dict) -> dict | None:
    """1 つのイベントを、画面に出す形に変換する。出さないものは None を返す。

    Strands は生成の途中経過を細かくイベントで返します。全部出すと情報が
    多すぎて何が起きているか分からなくなるので、ループの流れが見える
    最低限だけを通し、元のイベントは raw に添えます。画面では折りたたみの
    中に置いて、見たい人だけが開ける形にします。
    """
    if event.get("init_event_loop"):
        return {"type": "loop_start", "raw": _serializable(event)}

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
                "raw": _serializable(event),
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
                "raw": _serializable(event),
            }

    if "data" in event:
        # テキストは 1 文字ずつ届くこともあるので、生データは付けません
        return {"type": "text", "text": event["data"]}

    if "result" in event:
        return {"type": "done", "summary": _summarize_result(event["result"])}

    return None
