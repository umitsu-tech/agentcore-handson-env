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
    # 保存した plan ファイルを apply するときは変数を渡せない（terraform がエラーにする）。
    # `-var-file extra.json` のように値を空白で区切るオプションもあるので、引数の形ではなく
    # 中身で見分ける。plan ファイルは zip 形式なので先頭 2 バイトが PK になる
    # （-chdir するのでルートからの相対パスも見る）
    if [ "$CMD" = apply ]; then
      for arg in "${@:2}"; do
        case "$arg" in
          -*) ;;
          *)
            for f in "$arg" "$DIR/$arg"; do
              if [ -f "$f" ] && [ "$(head -c 2 "$f")" = PK ]; then
                exec terraform -chdir="$DIR" "$@"
              fi
            done
            ;;
        esac
      done
    fi
    # plan ファイルには変数の値が平文で入る。よく使う名前は .gitignore で除外しているが、
    # 名前は自由に付けられるので、保存するときは毎回注意を出す
    if [ "$CMD" = plan ]; then
      for arg in "${@:2}"; do
        case "$arg" in
          -out | -out=*)
            echo "注意: 保存した plan には変数の値が平文で入ります。コミットせず、apply が済んだら消してください" >&2
            ;;
        esac
      done
    fi
    # exec-file は復号した中身を一時的な名前付きパイプで渡し、{} をそのパスに置き換える。
    # terraform は拡張子で JSON かどうかを見るので、名前を .tfvars.json にする。
    # -var-file はサブコマンドの直後に置く。terraform はあとに書いた変数指定を優先するので、
    # 手で足した -var が暗号化した値に上書きされないようにするため。import のように
    # 最後に位置引数を取るサブコマンドでも、オプションの位置に収まる
    rest=""
    [ $# -gt 1 ] && rest=$(printf '%q ' "${@:2}")
    exec sops exec-file --filename secrets.tfvars.json "$VAR_FILE" \
      "terraform -chdir=$(printf '%q' "$DIR") $(printf '%q' "$CMD") -var-file={} $rest"
    ;;
  *)
    exec terraform -chdir="$DIR" "$@"
    ;;
esac
