#!/bin/bash
# 受講者の EC2 全台に同じコマンドを SSM で一斉に流し、結果を表で並べる。
# 人数ぶんを試しに立てるときに、主催者 1 人で次のことを確かめるためのもの（Issue #6、#93）。
#
#   deploy  全台で同時に agentcore deploy を流し、所要時間と成否を並べる。
#           受講者が一斉に deploy したときの待ち時間を見る。作った Runtime とスタックは消さない
#           （後片付けは scripts/cleanup-participant-resources.sh）
#   model   全台で Nova 2 Lite を 1 回呼び、通るかを並べる。終了時刻（handson_end_time）の前は
#           全員がモデルを呼べること、後は受講者ロールの Deny で AccessDenied になることを見る
#
# 使い方:
#   scripts/run-on-participants.sh deploy
#   scripts/run-on-participants.sh model
#   scripts/run-on-participants.sh model --only user01
#
# オプション:
#   --only <userNN,...>   対象を絞る。既定は受講者の EC2 すべて
#   --region <リージョン>  既定は ap-northeast-1（環境変数 AWS_REGION でも指定できる）
#   --project <名前>      Project タグの値。既定は agentcore-handson（terraform/handson の project_name）
#   -h, --help            この説明を表示する
#
# 対象は動いていて SSM につながる EC2 だけ（1 回に 50 台まで）。終了時刻のあとは EC2 が
# 止まっているので、Deny を確かめるときは 1 台だけ起こしてから --only で指定する。
# deploy は受講者と同じ handson ユーザーで流す。model は root で流すが、どちらも使うのは
# EC2 のロール（受講者ロール）の権限なので、受講者が呼んだときと同じ結果になる。
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PROJECT="agentcore-handson"
ONLY=""
MODE=""
MODEL_ID="jp.amazon.nova-2-lite-v1:0"

usage() {
  # ファイル先頭のコメントをそのまま説明文にする
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    deploy|model) MODE="$1"; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明な引数: $1" >&2; usage >&2; exit 1 ;;
  esac
done
if [ -z "$MODE" ]; then
  echo "deploy か model を指定してください" >&2
  usage >&2
  exit 1
fi

AWS=(aws --region "$REGION")

log() { printf '\n==> %s\n' "$*"; }
fail() { echo "エラー: $*" >&2; exit 1; }

# JSON の文字列として埋め込めるようにエスケープする（SSM のパラメータ用。build-ami.sh と同じ）
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# --- EC2 で流すコマンド ----------------------------------------------------------
# 最後に「RESULT <結果> <秒数>」の 1 行を出し、手元ではこの行を読む。
# SSM が返す標準出力は先頭 24,000 文字までなので、deploy の長いログはファイルに逃がし、
# 失敗したときだけ末尾を出す。
# $(...) の中にヒアドキュメントを書くと macOS の bash 3.2 が case の ) を読み違えるので read -d '' で受ける。
if [ "$MODE" = deploy ]; then
  read -r -d '' REMOTE <<'EOF' || true
LOG=/tmp/run-on-participants-deploy.log
START=$(date +%s)
if runuser -l handson -c 'cd ~/workspace && agentcore deploy --yes --target default' > "$LOG" 2>&1; then
  STATUS=ok
else
  STATUS=failed
fi
echo "RESULT $STATUS $(( $(date +%s) - START ))"
[ "$STATUS" = ok ] || tail -n 20 "$LOG"
EOF
  EXEC_TIMEOUT=1800
  POLL_INTERVAL=15
else
  read -r -d '' REMOTE <<'EOF' || true
MESSAGE=/tmp/run-on-participants-message.json
printf '%s' '[{"role":"user","content":[{"text":"Hello"}]}]' > "$MESSAGE"
START=$(date +%s)
if OUT=$(aws bedrock-runtime converse --region __REGION__ --model-id __MODEL_ID__ \
    --messages "file://$MESSAGE" --inference-config maxTokens=16 \
    --query stopReason --output text 2>&1); then
  STATUS=allowed
else
  case "$OUT" in
    *AccessDenied*) STATUS=denied ;;
    *) STATUS=error ;;
  esac
fi
echo "RESULT $STATUS $(( $(date +%s) - START ))"
[ "$STATUS" = allowed ] || printf '%s\n' "$OUT" | tail -n 5
EOF
  REMOTE=${REMOTE//__REGION__/$REGION}
  REMOTE=${REMOTE//__MODEL_ID__/$MODEL_ID}
  EXEC_TIMEOUT=120
  POLL_INTERVAL=5
fi

# --- 0. 前提の確認 --------------------------------------------------------------
command -v aws > /dev/null || fail "AWS CLI が見つかりません"
"${AWS[@]}" sts get-caller-identity > /dev/null 2>&1 \
  || fail "AWS の認証が通りません。aws login を実行してからやり直してください"

# --- 1. 対象の EC2 を決める -------------------------------------------------------
log "受講者の EC2 を探す（Project=${PROJECT}）"
# 「受講者名<TAB>インスタンス ID<TAB>状態」を受講者名の順に並べる
INSTANCES=$("${AWS[@]}" ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=tag-key,Values=Participant" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].[Tags[?Key=='Participant']|[0].Value, InstanceId, State.Name]" \
  --output text | sort)
if [ -n "$ONLY" ]; then
  INSTANCES=$(printf '%s\n' "$INSTANCES" | awk -v only=",$ONLY," 'index(only, "," $1 ",")')
fi
[ -n "$INSTANCES" ] || fail "対象の EC2 が見つかりません"

RUNNING_IDS=$(printf '%s\n' "$INSTANCES" | awk '$3 == "running" { print $2 }' | paste -sd, -)
[ -n "$RUNNING_IDS" ] || fail "動いている EC2 がありません"
ONLINE_IDS=" $("${AWS[@]}" ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$RUNNING_IDS" \
  --query "InstanceInformationList[?PingStatus=='Online'].InstanceId" --output text | tr '\t' ' ') "

TARGETS=""
IDS=()
while IFS=$'\t' read -r name id state; do
  if [ "$state" != running ]; then
    echo "飛ばす: $name ($id) は $state"
  elif [ "${ONLINE_IDS#* "$id" }" = "$ONLINE_IDS" ]; then
    echo "飛ばす: $name ($id) は SSM につながっていない"
  else
    TARGETS+="$name"$'\t'"$id"$'\n'
    IDS+=("$id")
  fi
done <<< "$INSTANCES"
[ "${#IDS[@]}" -gt 0 ] || fail "SSM につながる EC2 がありません"
[ "${#IDS[@]}" -le 50 ] || fail "1 回に送れるのは 50 台までです。--only で分けてください"
echo "対象: ${#IDS[@]} 台"

# --- 2. 一斉に送る ---------------------------------------------------------------
# 1 回の send-command で全台に送る。max-concurrency を 100% にして全台を同時に始め、
# max-errors も 100% にして、1 台が失敗しても残りを止めないようにする。
log "$MODE を全台に送る"
PARAMS='{"executionTimeout":["'"$EXEC_TIMEOUT"'"],"commands":["'"$(json_escape "$REMOTE")"'"]}'
COMMAND_ID=$("${AWS[@]}" ssm send-command --instance-ids "${IDS[@]}" \
  --document-name AWS-RunShellScript --comment "run-on-participants $MODE" \
  --parameters "$PARAMS" --max-concurrency 100% --max-errors 100% --timeout-seconds 300 \
  --query Command.CommandId --output text)
echo "コマンド ID: $COMMAND_ID"
SENT_AT=$SECONDS

# --- 3. 全台が終わるのを待つ ------------------------------------------------------
while true; do
  # 送った直後は一覧が空のことがあるので、空の行は数えない
  DONE=$("${AWS[@]}" ssm list-command-invocations --command-id "$COMMAND_ID" \
    --query 'CommandInvocations[].Status' --output text | tr '\t' '\n' \
    | awk 'NF && $1 != "Pending" && $1 != "InProgress" && $1 != "Delayed" { n++ } END { print n + 0 }')
  printf '\r終わった台数: %s / %s（経過 %s 秒）' "$DONE" "${#IDS[@]}" "$((SECONDS - SENT_AT))"
  [ "$DONE" -ge "${#IDS[@]}" ] && break
  sleep "$POLL_INTERVAL"
done
printf '\n'
ELAPSED=$((SECONDS - SENT_AT))

# --- 4. 結果を並べる -------------------------------------------------------------
log "結果"
RESULTS=""
DETAILS=""
while IFS=$'\t' read -r name id; do
  [ -n "$id" ] || continue
  OUT=$("${AWS[@]}" ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$id" \
    --query StandardOutputContent --output text 2> /dev/null || true)
  LINE=$(printf '%s\n' "$OUT" | awk '$1 == "RESULT" { print $2, $3; exit }')
  if [ -n "$LINE" ]; then
    RESULTS+="$name ${LINE}"$'\n'
  else
    # RESULT の行が無いのは、時間切れなどで EC2 側のコマンドが最後まで走らなかったとき
    SSM_STATUS=$("${AWS[@]}" ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$id" \
      --query Status --output text 2> /dev/null || echo Unknown)
    RESULTS+="$name ssm:$SSM_STATUS -"$'\n'
  fi
  # 通らなかったものは EC2 側が出した末尾のログを後ろにまとめて出す
  case "$LINE" in
    ok\ *|allowed\ *) ;;
    *) DETAILS+="--- $name ($id)"$'\n'"$(printf '%s\n' "$OUT" | grep -v '^RESULT ' | grep . || echo '（EC2 側の出力なし）')"$'\n' ;;
  esac
done <<< "$TARGETS"

# 日本語の見出しは 1 文字が 2 桁ぶんの幅なので、列の位置を空白で合わせてある
echo "受講者    結果          秒"
printf '%s' "$RESULTS" | awk '{ printf "%-9s %-12s %3s\n", $1, $2, $3 }'

echo
printf '%s' "$RESULTS" | awk '{ n[$2]++ } END { for (k in n) printf "%s: %d 台\n", k, n[k] }' | sort
if [ "$MODE" = deploy ]; then
  printf '%s' "$RESULTS" | awk '$2 == "ok" { s += $3; c++; if (min == "" || $3 < min) min = $3; if ($3 > max) max = $3 }
    END { if (c) printf "成功した deploy の所要時間: 最短 %d 秒 / 最長 %d 秒 / 平均 %d 秒\n", min, max, s / c }'
fi
echo "送ってから全台が終わるまで: ${ELAPSED} 秒"

if [ -n "$DETAILS" ]; then
  log "通らなかったものの末尾"
  printf '%s' "$DETAILS"
fi
