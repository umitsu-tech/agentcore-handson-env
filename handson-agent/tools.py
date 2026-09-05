"""エージェントが使えるツール。

ツールは「関数」です。@tool を付けて関数を書くと、その関数の説明文と引数が
そのままモデルに渡り、モデルが「この質問にはこのツールが要る」と判断したときに
呼ばれます。

説明文（docstring）はモデルへの指示そのものです。ここを書き換えると、
モデルがツールを選ぶかどうかが変わります。試してみてください。

ツールは文章ではなくデータ（dict や list）を返します。Strands がそれを JSON にして
モデルへ渡し、日本語の文章にして答えるのはモデルの仕事です。
"""

import json
from pathlib import Path

from strands import tool

DATA_FILE = Path(__file__).parent / "data" / "equipment.json"


def _load_equipment() -> list[dict]:
    return json.loads(DATA_FILE.read_text(encoding="utf-8"))


@tool
def search_equipment(keyword: str) -> list[dict]:
    """備品を名前やカテゴリで検索する。

    Args:
        keyword: 検索したい言葉。「ノートPC」「モニター」など

    Returns:
        見つかった備品のデータの一覧（id, name, category, status, borrower, due_date）。
        見つからなければ空リスト
    """
    return [
        item
        for item in _load_equipment()
        if keyword in item["name"] or keyword in item["category"]
    ]


@tool
def get_equipment_status(equipment_id: str) -> dict:
    """備品 ID を指定して、その備品の貸出状況を調べる。

    Args:
        equipment_id: 備品の ID。「PC-001」のような形式

    Returns:
        備品のデータ（id, name, category, status, borrower, due_date）。
        status が 貸出中 のときは borrower と due_date が入る。
        見つからなければ error を含む dict
    """
    for item in _load_equipment():
        if item["id"] == equipment_id:
            return item

    return {"error": "not_found", "equipment_id": equipment_id}


# ここに自分のツールを足してみましょう（ハンズオンの 2 番目のステップ）。
#
# たとえば、カテゴリを渡すと「いま借りられるもの」だけを返すツールを作ると、
# 「モニター借りたいんだけど空いてる？」に一発で答えられるようになります。
#
# ここでもツールはデータを返すだけにして、日本語にするのはモデルに任せます。
#
# @tool
# def find_available(category: str) -> list[dict]:
#     """指定したカテゴリで、いま貸出可能な備品を探す。
#
#     Args:
#         category: 「ノートPC」「モニター」などのカテゴリ名
#
#     Returns:
#         貸出可能な備品のデータの一覧（id, name, category, status, borrower, due_date）
#     """
#     ...
#
# 書けたら agent.py の TOOLS に足すのを忘れずに。
