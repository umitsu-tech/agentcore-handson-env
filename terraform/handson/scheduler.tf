# 終了時刻での自動停止（Issue #17 の保険）。消し忘れても翌日まで課金が伸びないようにする。
# 「停止」であって「削除」ではない。最終的な削除は人が cleanup スクリプトと destroy まで通す。
#
#   a. 受講者ロールに Deny（iam.tf の aws_iam_role_policy.deadline）
#   b. EventBridge Scheduler の一回きりスケジュールで EC2 を全台停止
#   c. 同じ時刻に ALB を削除（ALB は停止できない）
#
# ALB を Terraform の外で消すので、時刻を過ぎたあとは terraform destroy の一方向にする。
# apply を打つと ALB を作り直してしまう（docs/operations.md）。

locals {
  deadline_enabled = var.handson_end_time != null

  # RFC3339（オフセット付き）を 2 つに分ける。
  #   壁時計の時刻（2026-10-31T17:00:00）→ Scheduler の at() 式に timezone とあわせて渡す
  #   UTC の時刻（2026-10-31T08:00:00Z）  → IAM の DateGreaterThan に渡す
  # Terraform の formatdate / timeadd はオフセットを UTC に正規化しないので、
  # オフセットを取り出して自分で引く。
  deadline_wall   = local.deadline_enabled ? substr(var.handson_end_time, 0, 19) : null
  deadline_offset = local.deadline_enabled ? substr(var.handson_end_time, 19, -1) : null
  deadline_shift = local.deadline_enabled ? (
    local.deadline_offset == "Z" ? "0h" :
    format("%s%sh%sm",
      substr(local.deadline_offset, 0, 1) == "+" ? "-" : "",
      substr(local.deadline_offset, 1, 2),
      substr(local.deadline_offset, 4, 2),
    )
  ) : null
  deadline_utc = local.deadline_enabled ? formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timeadd("${local.deadline_wall}Z", local.deadline_shift)) : null
}

# Scheduler が EC2 の停止と ALB の削除を代わりに実行するためのロール。
# 対象をこの環境のインスタンスと ALB に限定する。
resource "aws_iam_role" "scheduler" {
  count = local.deadline_enabled ? 1 : 0
  name  = "${local.name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.deadline_enabled ? 1 : 0
  name  = "${local.name}-scheduler"
  role  = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StopParticipantInstances"
        Effect   = "Allow"
        Action   = "ec2:StopInstances"
        Resource = [for i in aws_instance.participant : i.arn]
      },
      {
        Sid      = "DeleteHandsonAlb"
        Effect   = "Allow"
        Action   = "elasticloadbalancing:DeleteLoadBalancer"
        Resource = aws_lb.this.arn
      },
    ]
  })
}

# universal target（aws-sdk）で API を直接呼ぶ。Lambda は置かない。
# 実行後はスケジュール自体を消す（action_after_completion = DELETE）ので、
# 時刻を過ぎたあとの destroy でスケジュールが見つからなくても問題ない（refresh で消えたと分かる）。
resource "aws_scheduler_schedule" "stop_instances" {
  count = local.deadline_enabled ? 1 : 0
  name  = "${local.name}-stop-instances"

  schedule_expression          = "at(${local.deadline_wall})"
  schedule_expression_timezone = var.handson_timezone
  action_after_completion      = "DELETE"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${data.aws_partition.current.partition}:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      InstanceIds = [for i in aws_instance.participant : i.id]
    })
  }
}

resource "aws_scheduler_schedule" "delete_alb" {
  count = local.deadline_enabled ? 1 : 0
  name  = "${local.name}-delete-alb"

  schedule_expression          = "at(${local.deadline_wall})"
  schedule_expression_timezone = var.handson_timezone
  action_after_completion      = "DELETE"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${data.aws_partition.current.partition}:scheduler:::aws-sdk:elasticloadbalancingv2:deleteLoadBalancer"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode({
      LoadBalancerArn = aws_lb.this.arn
    })
  }
}
