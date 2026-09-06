#!/bin/bash
# 受講者が agentcore deploy で作ったリソース（Terraform 管理外）を棚卸しし、
# --delete を付けたときだけ削除する。
#
# 使い方:
#   scripts/cleanup-participant-resources.sh              # 一覧だけ（何も消さない）
#   scripts/cleanup-participant-resources.sh --delete     # 一覧のあと削除する
#   scripts/cleanup-participant-resources.sh --prefix handson --region ap-northeast-1
#
# 対象は「名前が <prefix> で始まるもの」だけ。同じアカウントにある別案件の
# Runtime や EC2 には触らない。prefix の既定は handson で、agentcore.json の
# プロジェクト名 handsonPARTICIPANT（起動時に handsonuserNN へ置換）に合わせてある。
#
#   - CloudFormation スタック   AgentCore-<prefix>*      （agentcore deploy が CDK で作る。
#                                                          Runtime と実行ロールもこの中）
#   - AgentCore Runtime         <prefix>*                 （スタックを消せば消えるが、
#                                                          取り残しがあれば直接消す）
#   - IAM ロール                AgentCore-<prefix>*       （同上）
#   - CloudWatch ロググループ   /aws/bedrock-agentcore/runtimes/<prefix>*
#                                                         （スタックを消しても残る）
#
# ECR は対象にしない。deploy は CodeZip 方式で、受講者ごとのリポジトリは作られない。
# CDK のブートストラップ（cdk-hnb659fds-* のバケットと ECR）は次回も使うので触らない。
#
# 手順書では「終了時刻で自動停止 → このスクリプト → terraform destroy」の順にする。
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PREFIX="handson"
DELETE=false

usage() { sed -n '2,25p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --delete) DELETE=true; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

AWS=(aws --region "$REGION" --output text)

log() { printf '\n==> %s\n' "$*"; }

if ! "${AWS[@]}" sts get-caller-identity --query Account > /dev/null 2>&1; then
  echo "エラー: AWS の認証が通りません。aws login を実行してからやり直してください" >&2
  exit 1
fi

# --- 棚卸し -------------------------------------------------------------------

log "CloudFormation スタック（AgentCore-${PREFIX}*）"
STACKS=$("${AWS[@]}" cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE ROLLBACK_COMPLETE CREATE_FAILED DELETE_FAILED IMPORT_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'AgentCore-${PREFIX}')].StackName" | tr '\t' '\n' | sed '/^$/d' || true)
printf '%s\n' "${STACKS:-(なし)}"

log "AgentCore Runtime（${PREFIX}*）"
RUNTIMES=$("${AWS[@]}" bedrock-agentcore-control list-agent-runtimes \
  --query "agentRuntimes[?starts_with(agentRuntimeName, '${PREFIX}')].[agentRuntimeName, agentRuntimeId]" || true)
printf '%s\n' "${RUNTIMES:-(なし)}"

log "IAM ロール（AgentCore-${PREFIX}*）"
ROLES=$("${AWS[@]}" iam list-roles \
  --query "Roles[?starts_with(RoleName, 'AgentCore-${PREFIX}')].RoleName" | tr '\t' '\n' | sed '/^$/d' || true)
printf '%s\n' "${ROLES:-(なし)}"

log "CloudWatch ロググループ（/aws/bedrock-agentcore/runtimes/${PREFIX}*）"
LOG_GROUPS=$("${AWS[@]}" logs describe-log-groups \
  --log-group-name-prefix "/aws/bedrock-agentcore/runtimes/${PREFIX}" \
  --query 'logGroups[].logGroupName' | tr '\t' '\n' | sed '/^$/d' || true)
printf '%s\n' "${LOG_GROUPS:-(なし)}"

if [ "$DELETE" != true ]; then
  echo
  echo "一覧だけ表示しました。削除するときは --delete を付けて実行してください"
  exit 0
fi

# --- 削除 -----------------------------------------------------------------------
# スタックを先に消す。Runtime と実行ロールはスタックの中なので、ここで大半が片付く。
# 全部の削除を投げてから待つ（受講者数ぶん順番に待つと時間がかかる）。

if [ -n "$STACKS" ]; then
  log "スタックを削除する"
  for s in $STACKS; do
    echo "delete-stack: $s"
    "${AWS[@]}" cloudformation delete-stack --stack-name "$s"
  done
  for s in $STACKS; do
    echo "wait: $s"
    if ! "${AWS[@]}" cloudformation wait stack-delete-complete --stack-name "$s"; then
      echo "警告: $s の削除が完了しませんでした。コンソールでイベントを確認してください" >&2
    fi
  done
fi

# スタック削除後に取り残された Runtime とロール（手動で作ったもの、DELETE_FAILED の残骸など）
log "取り残しを確認する"
LEFT_RUNTIMES=$("${AWS[@]}" bedrock-agentcore-control list-agent-runtimes \
  --query "agentRuntimes[?starts_with(agentRuntimeName, '${PREFIX}')].agentRuntimeId" | tr '\t' '\n' | sed '/^$/d' || true)
for id in $LEFT_RUNTIMES; do
  echo "delete-agent-runtime: $id"
  "${AWS[@]}" bedrock-agentcore-control delete-agent-runtime --agent-runtime-id "$id" > /dev/null
done

LEFT_ROLES=$("${AWS[@]}" iam list-roles \
  --query "Roles[?starts_with(RoleName, 'AgentCore-${PREFIX}')].RoleName" | tr '\t' '\n' | sed '/^$/d' || true)
for r in $LEFT_ROLES; do
  echo "delete-role: $r"
  for p in $("${AWS[@]}" iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn'); do
    "${AWS[@]}" iam detach-role-policy --role-name "$r" --policy-arn "$p"
  done
  for p in $("${AWS[@]}" iam list-role-policies --role-name "$r" --query 'PolicyNames'); do
    "${AWS[@]}" iam delete-role-policy --role-name "$r" --policy-name "$p"
  done
  "${AWS[@]}" iam delete-role --role-name "$r"
done

if [ -n "$LOG_GROUPS" ]; then
  log "ロググループを削除する"
  for g in $LOG_GROUPS; do
    echo "delete-log-group: $g"
    "${AWS[@]}" logs delete-log-group --log-group-name "$g"
  done
fi

log "完了。次は terraform destroy で EC2・ALB・VPC を消してください"
