#!/bin/bash
# 受講者情報（userNN ごとの URL とパスワード）を手順書サイトの /participants/data.json に置く。
# 中身は terraform/handson の output から組み立てる。git には入れず、S3 に直接置く。
# ページ側（participants.html）は Basic 認証の裏にあるので、合言葉を知っている人しか読めない。
#
#   guide/publish-participants.sh            # 置く（キャッシュ削除まで）
#   guide/publish-participants.sh --dry-run  # 置かずに中身だけ表示する
#   guide/publish-participants.sh --remove   # 消す（受講環境を destroy したあとに）
#
# 受講環境（terraform/handson）と手順書（terraform/guide）の両方が init/apply 済みであること。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HANDSON_TF="$HERE/../terraform/handson"
GUIDE_TF="$HERE/../terraform/guide"
KEY="participants/data.json"
MODE="publish"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --remove) MODE="remove"; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! aws sts get-caller-identity --query Account --output text > /dev/null 2>&1; then
  echo "エラー: AWS の認証が通りません。aws login を実行してからやり直してください" >&2
  exit 1
fi

BUCKET=$(terraform -chdir="$GUIDE_TF" output -raw bucket_name)
DIST_ID=$(terraform -chdir="$GUIDE_TF" output -raw distribution_id)
PAGE_URL=$(terraform -chdir="$GUIDE_TF" output -raw participants_url)

invalidate() {
  echo "==> CloudFront のキャッシュを消す: $DIST_ID"
  aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/participants*" --query 'Invalidation.Id' --output text
}

if [ "$MODE" = "remove" ]; then
  echo "==> 消す: s3://$BUCKET/$KEY"
  aws s3 rm "s3://$BUCKET/$KEY"
  invalidate
  exit 0
fi

# terraform output -json は sensitive な値もそのまま出る（パスワードはここで初めて手元に来る）
DATA=$(terraform -chdir="$HANDSON_TF" output -json | python3 -c '
import json, sys, datetime
o = json.load(sys.stdin)
urls = o["participant_urls"]["value"]
ui = o["participant_ui_urls"]["value"]
pw = o["participant_passwords"]["value"]
rows = [
    {"id": k, "editor_url": urls[k], "ui_url": ui[k], "password": pw[k]}
    for k in sorted(urls)
]
print(json.dumps({
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "participants": rows,
}, ensure_ascii=False, indent=2))
')

COUNT=$(printf '%s' "$DATA" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["participants"]))')

if [ "$MODE" = "dry-run" ]; then
  echo "==> $COUNT 人分。置き先: s3://$BUCKET/$KEY"
  printf '%s\n' "$DATA" | python3 -c '
import json, sys
for r in json.load(sys.stdin)["participants"]:
    print(f"{r[\"id\"]:8} {r[\"editor_url\"]:48} {r[\"password\"]}")
'
  exit 0
fi

echo "==> 置く: $COUNT 人分 -> s3://$BUCKET/$KEY"
printf '%s\n' "$DATA" | aws s3 cp - "s3://$BUCKET/$KEY" --content-type "application/json; charset=utf-8" --cache-control "no-cache"
invalidate

echo "==> 受講者情報ページ: $PAGE_URL"
echo "Basic 認証のユーザー名と合言葉は terraform/guide/terraform.tfvars の participants_user / participants_password"
