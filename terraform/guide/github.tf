# GitHub Actions から手順書を自動配信するための認証（Issue #52）。
# 長期のアクセスキーは置かず、GitHub の OIDC トークンでこのロールを assume させる。
# ロールが使えるのは、このリポジトリの main ブランチで動くワークフローだけ。
# 権限は手順書のバケットへの書き込みと、このディストリビューションのキャッシュ削除だけ。

# GitHub の OIDC トークンの sub は、2026-07-15 以降に作られたリポジトリでは
# repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch> の形（immutable subject claim）になる。
# それ以前の形（ID 無し）も併記して、どちらでも assume できるようにする。
locals {
  github_subjects = var.github_repository == null ? [] : concat(
    ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"],
    var.github_owner_id != null && var.github_repository_id != null ? [
      format("repo:%s@%s/%s@%s:ref:refs/heads/%s",
        split("/", var.github_repository)[0], var.github_owner_id,
        split("/", var.github_repository)[1], var.github_repository_id,
      var.github_branch)
    ] : []
  )
}

# OIDC プロバイダーはアカウントに 1 つあればよく、他のリポジトリと共用する。
# 既にある前提で参照する（無ければ IAM コンソールか別の Terraform で作る）
data "aws_iam_openid_connect_provider" "github" {
  count = var.github_repository != null ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  count = var.github_repository != null ? 1 : 0
  name  = "${local.name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.github_subjects
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  count = var.github_repository != null ? 1 : 0
  name  = "${local.name}-publish"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.site.arn
      },
      {
        Sid      = "SyncObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.site.arn}/*"
      },
      {
        Sid      = "Invalidate"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.site.arn
      },
    ]
  })
}
