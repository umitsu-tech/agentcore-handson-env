#!/bin/bash
# SOPS で暗号化した設定を復号しながら terraform を動かす（Issue #79）。
#
# 使い方:
#   scripts/tf.sh handson init
#   scripts/tf.sh handson plan
#   scripts/tf.sh handson apply
#   scripts/tf.sh guide destroy
#   scripts/tf.sh handson output -raw alb_dns_name   # 変数が要らないサブコマンドもそのまま通す
#
# 渡すものは 2 つ。
#   - terraform/secrets.enc.env          Cloudflare の API トークンと state のバケット。環境変数にする
#   - terraform/<handson|guide>/secrets.enc.json  tfvars を JSON にしたもの。-var-file にする
# どちらも sops が実行中だけ復号して子プロセスに渡すので、平文のファイルは手元に残らない。
#
# 秘密鍵は ~/.config/sops/age/keys.txt に置く。macOS の sops は既定で
# ~/Library/Application Support/sops/age/ を探すので、場所は SOPS_AGE_KEY_FILE で教える
# （OS で置き場所が変わらないように、ここで既定値を入れる）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

usage() {
  sed -n '2,9p' "$0" >&2
  exit 1
}

[ $# -ge 2 ] || usage
TARGET="$1"
shift
case "$TARGET" in
  handson | guide) ;;
  *) usage ;;
esac

DIR="$ROOT_DIR/terraform/$TARGET"
ENV_FILE="$ROOT_DIR/terraform/secrets.enc.env"
VAR_FILE="$DIR/secrets.enc.json"
CMD="$1"

# 1 段目: secrets.enc.env を環境変数にして、自分自身をもう一度呼ぶ
if [ "${_TF_SH_INNER:-}" != 1 ]; then
  exec sops exec-env "$ENV_FILE" "_TF_SH_INNER=1 $(printf '%q ' "$0" "$TARGET" "$@")"
fi

# 2 段目: 環境変数（CLOUDFLARE_API_TOKEN、TF_STATE_BUCKET、TF_STATE_REGION）が入った状態
case "$CMD" in
  init)
    exec terraform -chdir="$DIR" "$@" \
      -backend-config="bucket=$TF_STATE_BUCKET" \
      -backend-config="region=$TF_STATE_REGION"
    ;;
  plan | apply | destroy | import | refresh | console)
    # 保存した plan ファイルを apply するときは変数を渡せない（terraform がエラーにする）
    if [ "$CMD" = apply ]; then
      for arg in "${@:2}"; do
        case "$arg" in
          -*) ;;
          *) exec terraform -chdir="$DIR" "$@" ;;
        esac
      done
    fi
    # exec-file は復号した中身を一時的な名前付きパイプで渡し、{} をそのパスに置き換える。
    # terraform は拡張子で JSON かどうかを見るので、名前を .tfvars.json にする
    exec sops exec-file --filename secrets.tfvars.json "$VAR_FILE" \
      "terraform -chdir=$(printf '%q' "$DIR") $(printf '%q ' "$@")-var-file={}"
    ;;
  *)
    exec terraform -chdir="$DIR" "$@"
    ;;
esac
