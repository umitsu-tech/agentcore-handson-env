"""エージェントが使えるツール。

ツールは「関数」です。@tool を付けて関数を書くと、その関数の説明文と引数が
そのままモデルに渡り、モデルが「この質問にはこのツールが要る」と判断したときに
呼ばれます。

説明文（docstring）はモデルへの指示そのものです。ここを書き換えると、
モデルがツールを選ぶかどうかが変わります。試してみてください。
"""

import json
from pathlib import Path

from strands import tool

DATA_FILE = Path(__file__).parent / "data" / "equipment.json"


def _load_equipment() -> list[dict]:
    return json.loads(DATA_FILE.read_text(encoding="utf-8"))


@tool
def search_equipment(keyword: str) -> str:
    """備品を名前やカテゴリで検索する。

    Args:
        keyword: 検索したい言葉。「ノートPC」「モニター」など

    Returns:
        見つかった備品の一覧
    """
    items = [
        item
        for item in _load_equipment()
        if keyword in item["name"] or keyword in item["category"]
    ]
    if not items:
        return f"「{keyword}」に一致する備品は見つかりませんでした。"

    lines = [
        f"{item['id']} / {item['name']}（{item['category']}）— {item['status']}"
        for item in items
    ]
    return "\n".join(lines)


@tool
def get_equipment_status(equipment_id: str) -> str:
    """備品 ID を指定して、その備品の貸出状況を調べる。

    Args:
        equipment_id: 備品の ID。「PC-001」のような形式

    Returns:
        貸出状況。貸出中なら借りている人と返却予定日も返す
    """
    for item in _load_equipment():
        if item["id"] == equipment_id:
            if item["status"] == "貸出中":
                return (
                    f"{item['name']}（{item['id']}）は貸出中です。"
                    f"{item['borrower']}さんが借りていて、返却予定日は {item['due_date']} です。"
                )
            return f"{item['name']}（{item['id']}）の状態は「{item['status']}」です。"

    return f"{equipment_id} という備品は登録されていません。"


# ここに自分のツールを足してみましょう（ハンズオンの 2 番目のステップ）。
#
# たとえば、カテゴリを渡すと「いま借りられるもの」だけを返すツールを作ると、
# 「モニター借りたいんだけど空いてる？」に一発で答えられるようになります。
#
# @tool
# def find_available(category: str) -> str:
#     """指定したカテゴリで、いま貸出可能な備品を探す。
#
#     Args:
#         category: 「ノートPC」「モニター」などのカテゴリ名
#
#     Returns:
#         貸出可能な備品の一覧
#     """
#     ...
#
# 書けたら agent.py の TOOLS に足すのを忘れずに。
