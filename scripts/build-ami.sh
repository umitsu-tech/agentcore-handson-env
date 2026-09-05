#!/bin/bash
# 受講者用の AMI を 1 本で焼き直す。
#
# ワークスペース（handson-agent/ と handson-ui/）を tar.gz にして S3 に上げ、
# EC2 を 1 台起動して scripts/setup-instance.sh を流し、再起動後に動作を確認してから
# AMI を作り、EC2 を消す。途中で失敗しても EC2 は残さない（--keep-instance 指定時を除く）。
#
# 使い方:
#   scripts/build-ami.sh [オプション]
#
# オプション:
#   --bucket <名前>        資材バケット。既定は agentcore-handson-assets-<アカウントID>
#                          （環境変数 ASSET_BUCKET でも指定できる。無ければ作る）
#   --instance-type <型>   焼くときのインスタンスタイプ。既定は t4g.small
#   --volume-size <GiB>    ルートボリュームのサイズ。既定は 15（Issue #15 の結論）
#   --region <リージョン>   既定は ap-northeast-1（環境変数 AWS_REGION でも指定できる）
#   --subnet-id <ID>       起動するサブネット。既定はデフォルト VPC のサブネット
#   --skip-upload          tar.gz の作成と S3 アップロードを飛ばし、S3 にあるものを使う
#   --keep-instance        終了時に EC2 を消さない（中を見て調べたいとき用）
#   --prune                新しい AMI 以外の agentcore-handson-* の AMI とスナップショットを消す
#   -h, --help             この説明を表示する
#
# 前提: AWS CLI v2 と tar。認証は aws login で済ませておく。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/scripts/setup-instance.sh"
ARCHIVE_NAME="handson-workspace.tar.gz"
AMI_PREFIX="agentcore-handson"
ROLE_NAME="${AMI_PREFIX}-ami-builder"
BASE_AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"

REGION="${AWS_REGION:-ap-northeast-1}"
BUCKET="${ASSET_BUCKET:-}"
INSTANCE_TYPE="t4g.small"
VOLUME_SIZE=15
SUBNET_ID=""
SKIP_UPLOAD=false
KEEP_INSTANCE=false
PRUNE=false

usage() {
  # ファイル先頭のコメントをそのまま説明文にする
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2 ;;
    --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
    --volume-size) VOLUME_SIZE="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --subnet-id) SUBNET_ID="$2"; shift 2 ;;
    --skip-upload) SKIP_UPLOAD=true; shift ;;
    --keep-instance) KEEP_INSTANCE=true; shift ;;
    --prune) PRUNE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "不明なオプション: $1" >&2; usage >&2; exit 1 ;;
  esac
done

AWS=(aws --region "$REGION")
INSTANCE_ID=""
WORK_DIR="$(mktemp -d)"

log() { printf '\n==> %s\n' "$*"; }
fail() { echo "エラー: $*" >&2; exit 1; }

# JSON の文字列として埋め込めるようにエスケープする（SSM のパラメータ用）
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# 終了時の後片付け。成功でも失敗でも EC2 を残さない
cleanup() {
  local status=$?
  if [ -n "$INSTANCE_ID" ]; then
    if $KEEP_INSTANCE; then
      echo "EC2 $INSTANCE_ID は残してあります。aws ssm start-session --target $INSTANCE_ID で入れます。不要になったら terminate してください"
    else
      log "EC2 $INSTANCE_ID を削除する"
      "${AWS[@]}" ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null || true
      "${AWS[@]}" ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" || true
    fi
  fi
  rm -rf "$WORK_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# SSM 経由でコマンドを実行し、標準出力を表示する。SSM 側の状態が Success 以外なら 1 を返す。
# 使い方: ssm_run <実行タイムアウト秒> <コマンド>...
ssm_run() {
  local timeout=$1; shift
  local params='{"executionTimeout":["'"$timeout"'"],"commands":['
  local sep="" c
  for c in "$@"; do
    params+="${sep}\"$(json_escape "$c")\""
    sep=","
  done
  params+=']}'

  local cmd_id status
  cmd_id=$("${AWS[@]}" ssm send-command --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript --parameters "$params" \
    --query 'Command.CommandId' --output text)
  while true; do
    status=$("${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
      --query Status --output text 2> /dev/null || echo Pending)
    case "$status" in
      Pending|InProgress|Delayed) printf '.' >&2; sleep 15 ;;
      *) break ;;
    esac
  done
  printf '\n' >&2
  "${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query StandardOutputContent --output text
  "${AWS[@]}" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query StandardErrorContent --output text >&2
  [ "$status" = "Success" ]
}

wait_ssm_online() {
  local i status
  for i in $(seq 1 60); do
    status=$("${AWS[@]}" ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2> /dev/null || echo None)
    [ "$status" = "Online" ] && return 0
    printf '.' >&2
    sleep 10
  done
  return 1
}

# --- 0. 前提の確認 --------------------------------------------------------------
command -v aws > /dev/null || fail "AWS CLI が見つかりません"
[ -f "$SETUP_SCRIPT" ] || fail "$SETUP_SCRIPT がありません"

ACCOUNT_ID=$("${AWS[@]}" sts get-caller-identity --query Account --output text 2> /dev/null) \
  || fail "AWS の認証が通りません。aws login を実行してからやり直してください"
[ -n "$BUCKET" ] || BUCKET="${AMI_PREFIX}-assets-${ACCOUNT_ID}"

echo "アカウント: $ACCOUNT_ID / リージョン: $REGION"
echo "資材バケット: s3://$BUCKET/$ARCHIVE_NAME"
echo "インスタンスタイプ: $INSTANCE_TYPE / ルートボリューム: ${VOLUME_SIZE}GiB"

# --- 1. ワークスペースを tar.gz にして S3 へ ------------------------------------
if ! "${AWS[@]}" s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
  log "資材バケット $BUCKET を作る"
  if [ "$REGION" = "us-east-1" ]; then
    "${AWS[@]}" s3api create-bucket --bucket "$BUCKET" > /dev/null
  else
    "${AWS[@]}" s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=$REGION" > /dev/null
  fi
  "${AWS[@]}" s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

if $SKIP_UPLOAD; then
  log "アップロードを飛ばす。S3 にある $ARCHIVE_NAME をそのまま使う"
  "${AWS[@]}" s3api head-object --bucket "$BUCKET" --key "$ARCHIVE_NAME" > /dev/null \
    || fail "s3://$BUCKET/$ARCHIVE_NAME がありません。--skip-upload を外してください"
else
  log "ワークスペースを $ARCHIVE_NAME にまとめる"
  ARCHIVE="$WORK_DIR/$ARCHIVE_NAME"
  # COPYFILE_DISABLE は macOS の tar が ._ 付きのメタデータファイルを混ぜないようにする
  (cd "$REPO_ROOT" && COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" \
    --exclude node_modules --exclude .venv --exclude frontend/dist \
    --exclude __pycache__ --exclude .DS_Store \
    handson-agent handson-ui)
  if tar -tzf "$ARCHIVE" | grep -qE '(^|/)(node_modules|\.venv|dist)(/|$)'; then
    fail "tar.gz に node_modules / .venv / dist が混ざっています"
  fi
  echo "サイズ: $(du -h "$ARCHIVE" | cut -f1)"

  log "S3 にアップロードする"
  "${AWS[@]}" s3 cp "$ARCHIVE" "s3://$BUCKET/$ARCHIVE_NAME"
fi

# --- 2. AMI 作成用の IAM ロール（固定名で使い回す） -------------------------------
# 受講者用のロールは Terraform が作るが、AMI は terraform apply より前に要るので
# ここで別に持つ。S3 の読み取りと SSM の接続だけ。
log "IAM ロール $ROLE_NAME を用意する"
if ! "${AWS[@]}" iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
  "${AWS[@]}" iam create-role --role-name "$ROLE_NAME" \
    --description "Used only while building the agentcore-handson AMI (scripts/build-ami.sh)" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    > /dev/null
fi
"${AWS[@]}" iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
"${AWS[@]}" iam put-role-policy --role-name "$ROLE_NAME" --policy-name read-workspace-archive \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${BUCKET}/${ARCHIVE_NAME}\"},
    {\"Effect\":\"Allow\",\"Action\":\"s3:ListBucket\",\"Resource\":\"arn:aws:s3:::${BUCKET}\"}]}"
if ! "${AWS[@]}" iam get-instance-profile --instance-profile-name "$ROLE_NAME" > /dev/null 2>&1; then
  "${AWS[@]}" iam create-instance-profile --instance-profile-name "$ROLE_NAME" > /dev/null
fi
if ! "${AWS[@]}" iam get-instance-profile --instance-profile-name "$ROLE_NAME" \
    --query 'InstanceProfile.Roles[].RoleName' --output text | grep -qw "$ROLE_NAME"; then
  "${AWS[@]}" iam add-role-to-instance-profile --instance-profile-name "$ROLE_NAME" --role-name "$ROLE_NAME"
fi

# --- 3. EC2 を起動する ---------------------------------------------------------
log "ベース AMI とサブネットを決める"
BASE_AMI=$("${AWS[@]}" ssm get-parameters --names "$BASE_AMI_PARAM" \
  --query 'Parameters[0].Value' --output text)
[ "$BASE_AMI" != "None" ] || fail "AL2023 の AMI が引けません（$BASE_AMI_PARAM）"
ROOT_DEVICE=$("${AWS[@]}" ec2 describe-images --image-ids "$BASE_AMI" \
  --query 'Images[0].RootDeviceName' --output text)
if [ -z "$SUBNET_ID" ]; then
  SUBNET_ID=$("${AWS[@]}" ec2 describe-subnets --filters Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' --output text)
  [ "$SUBNET_ID" != "None" ] || fail "デフォルト VPC のサブネットが見つかりません。--subnet-id で指定してください"
fi
echo "ベース AMI: $BASE_AMI（ルートデバイス $ROOT_DEVICE）/ サブネット: $SUBNET_ID"

# user_data は setup-instance.sh の先頭（shebang の直後）にバケット名の export を足したもの
USER_DATA="$WORK_DIR/user-data.sh"
{
  head -n 1 "$SETUP_SCRIPT"
  echo "export ASSET_BUCKET='$BUCKET'"
  echo "export ASSET_KEY='$ARCHIVE_NAME'"
  tail -n +2 "$SETUP_SCRIPT"
} > "$USER_DATA"

log "EC2 を起動する"
# 作ったばかりのインスタンスプロファイルは EC2 側に見えるまで数秒かかるので、その間だけ待って再試行する
for attempt in $(seq 1 6); do
  if INSTANCE_ID=$("${AWS[@]}" ec2 run-instances \
      --image-id "$BASE_AMI" --instance-type "$INSTANCE_TYPE" --subnet-id "$SUBNET_ID" \
      --associate-public-ip-address \
      --iam-instance-profile "Name=$ROLE_NAME" \
      --user-data "file://$USER_DATA" \
      --block-device-mappings "[{\"DeviceName\":\"$ROOT_DEVICE\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
      --metadata-options HttpTokens=required,HttpEndpoint=enabled \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${AMI_PREFIX}-ami-builder},{Key=Project,Value=$AMI_PREFIX}]" \
      --query 'Instances[0].InstanceId' --output text 2> "$WORK_DIR/run-instances.err"); then
    break
  fi
  INSTANCE_ID=""
  if grep -q "Invalid IAM Instance Profile" "$WORK_DIR/run-instances.err" && [ "$attempt" -lt 6 ]; then
    sleep 10
    continue
  fi
  cat "$WORK_DIR/run-instances.err" >&2
  fail "EC2 の起動に失敗しました"
done
[ -n "$INSTANCE_ID" ] || fail "EC2 の起動に失敗しました"
echo "インスタンス: $INSTANCE_ID"

# --- 4. セットアップの完了を待って確認する ----------------------------------------
log "起動と SSM の接続を待つ"
"${AWS[@]}" ec2 wait instance-running --instance-ids "$INSTANCE_ID"
wait_ssm_online || fail "SSM で $INSTANCE_ID に接続できません"

log "setup-instance.sh（cloud-init）の完了を待つ。10 分前後かかる"
# cloud-init 自体の警告（終了コード 2）では止めず、setup-instance.sh が最後まで走ったかを
# 末尾の「セットアップ完了」で判定する
if ! ssm_run 3600 "cloud-init status --wait > /dev/null || true" "cloud-init status --long" \
    "grep -q 'セットアップ完了' /var/log/cloud-init-output.log"; then
  echo "--- /var/log/cloud-init-output.log の末尾 ---" >&2
  ssm_run 60 "tail -n 60 /var/log/cloud-init-output.log" >&2 || true
  fail "setup-instance.sh が失敗しました"
fi

# setup-instance.sh はサービスを enable するだけなので、再起動して「起動すれば動く」ことを確かめる。
# 受講者の EC2 は AMI から起動するだけなので、この確認が本番と同じ条件になる
log "再起動して自動起動を確かめる"
BOOT_ID_BEFORE=$(ssm_run 60 "cat /proc/sys/kernel/random/boot_id")
"${AWS[@]}" ec2 reboot-instances --instance-ids "$INSTANCE_ID"
sleep 20
for _ in $(seq 1 40); do
  BOOT_ID_AFTER=$(ssm_run 60 "cat /proc/sys/kernel/random/boot_id" 2> /dev/null || true)
  if [ -n "$BOOT_ID_AFTER" ] && [ "$BOOT_ID_AFTER" != "$BOOT_ID_BEFORE" ]; then
    break
  fi
  sleep 10
done
[ "${BOOT_ID_AFTER:-}" != "$BOOT_ID_BEFORE" ] || fail "再起動が確認できません"

log "サービスと疎通を確認する"
CHECK_SCRIPT='
set -e
systemctl is-active code-server@handson handson-ui
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null http://localhost:3000/api/context && break
  sleep 2
done
echo "code-server /healthz -> $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)"
echo "handson-ui /api/context -> $(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/context)"
curl -fsS -o /dev/null http://localhost:8080/healthz
curl -fsS -o /dev/null http://localhost:3000/api/context
echo "=== 再起動後のメモリ ==="
free -m
echo "=== セットアップ時の使用量（/var/log/handson-setup-usage.log） ==="
cat /var/log/handson-setup-usage.log
'
ssm_run 300 "$CHECK_SCRIPT" || fail "動作確認に失敗しました。--keep-instance を付けて流し直すと中を調べられます"

# --- 5. AMI を作る -------------------------------------------------------------
AMI_NAME="${AMI_PREFIX}-$(date +%Y%m%d-%H%M)"
log "AMI $AMI_NAME を作る"
AMI_ID=$("${AWS[@]}" ec2 create-image --instance-id "$INSTANCE_ID" --name "$AMI_NAME" \
  --description "agentcore-handson 受講者用（${INSTANCE_TYPE} / ${VOLUME_SIZE}GiB で作成）" \
  --tag-specifications \
    "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=$AMI_PREFIX}]" \
    "ResourceType=snapshot,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=$AMI_PREFIX}]" \
  --query ImageId --output text)
echo "AMI: $AMI_ID"

# wait image-available は 15 秒 × 40 回で諦めるので、数回まわす
for _ in $(seq 1 4); do
  if "${AWS[@]}" ec2 wait image-available --image-ids "$AMI_ID" 2> /dev/null; then
    break
  fi
done
AMI_STATE=$("${AWS[@]}" ec2 describe-images --image-ids "$AMI_ID" --query 'Images[0].State' --output text)
[ "$AMI_STATE" = "available" ] || fail "AMI $AMI_ID の状態が $AMI_STATE のままです"

# --- 6. EC2 を消す（cleanup にも同じ処理があるが、ここで待って結果を見せる） --------
if ! $KEEP_INSTANCE; then
  log "EC2 $INSTANCE_ID を削除する"
  "${AWS[@]}" ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null
  "${AWS[@]}" ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
  INSTANCE_ID=""
fi

# --- 7. 古い AMI の掃除（--prune のときだけ） ------------------------------------
if $PRUNE; then
  log "古い AMI とスナップショットを消す"
  "${AWS[@]}" ec2 describe-images --owners self --filters "Name=name,Values=${AMI_PREFIX}-*" \
    --query "Images[?ImageId!='${AMI_ID}'].[ImageId,Name,join(',',BlockDeviceMappings[].Ebs.SnapshotId)]" \
    --output text | while read -r old_id old_name snapshots; do
      [ -n "$old_id" ] || continue
      echo "deregister $old_id ($old_name)"
      "${AWS[@]}" ec2 deregister-image --image-id "$old_id"
      for snap in ${snapshots//,/ }; do
        echo "delete snapshot $snap"
        "${AWS[@]}" ec2 delete-snapshot --snapshot-id "$snap"
      done
    done
fi

# --- 8. 結果 -------------------------------------------------------------------
log "完了"
echo "AMI 名: $AMI_NAME"
echo "AMI ID: $AMI_ID"
TFVARS="$REPO_ROOT/terraform/terraform.tfvars"
if [ -f "$TFVARS" ] && grep -qE '^ami_id[[:space:]]*=' "$TFVARS"; then
  sed -i.bak -E "s|^(ami_id[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"$AMI_ID\"|" "$TFVARS"
  rm -f "$TFVARS.bak"
  echo "terraform/terraform.tfvars の ami_id を $AMI_ID に書き換えました"
else
  echo "terraform/terraform.tfvars に ami_id = \"$AMI_ID\" を設定してください"
fi
