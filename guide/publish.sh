#!/bin/bash
# 手順書（guide/site/）を S3 に同期し、CloudFront のキャッシュを消す。
# 内容を直したらこれを 1 回打つだけ。Terraform は触らない。
#
#   guide/publish.sh            # 同期 + キャッシュ削除
#   guide/publish.sh --dry-run  # 何が上がるかだけ見る
#
# 同期先は guide/terraform の output から取る（terraform init 済みであること）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SITE_DIR="$HERE/site"
TF_DIR="$HERE/terraform"
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! aws sts get-caller-identity --query Account --output text > /dev/null 2>&1; then
  echo "エラー: AWS の認証が通りません。aws login を実行してからやり直してください" >&2
  exit 1
fi

BUCKET=$(terraform -chdir="$TF_DIR" output -raw bucket_name)
DIST_ID=$(terraform -chdir="$TF_DIR" output -raw distribution_id)
URL=$(terraform -chdir="$TF_DIR" output -raw guide_url)

echo "==> 同期: $SITE_DIR -> s3://$BUCKET/"
if [ "$DRY_RUN" = true ]; then
  aws s3 sync "$SITE_DIR" "s3://$BUCKET/" --delete --dryrun
  exit 0
fi
aws s3 sync "$SITE_DIR" "s3://$BUCKET/" --delete

echo "==> CloudFront のキャッシュを消す: $DIST_ID"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" --query 'Invalidation.Id' --output text

echo "==> 公開先: $URL"
echo "反映まで 1 分ほどかかることがあります"
