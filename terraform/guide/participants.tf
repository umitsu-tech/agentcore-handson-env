# 受講者情報ページ（/participants.html と /participants/data.json）だけを Basic 認証で守る。
# 手順書の他のページは誰でも開ける。認証は CloudFront Function（viewer-request）で行い、
# ユーザー名と合言葉は tfvars（git 管理外）から渡す。
# data.json の中身は Terraform では扱わない。../../guide/publish-participants.sh が S3 に直接置く。

variable "participants_user" {
  description = "受講者情報ページの Basic 認証のユーザー名。当日その場で伝える"
  type        = string
  default     = "handson"
}

variable "participants_password" {
  description = "受講者情報ページの Basic 認証の合言葉。当日その場で口頭で伝える。tfvars に書く（git 管理外）"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.participants_password) >= 8
    error_message = "participants_password は 8 文字以上にしてください。"
  }
}

resource "aws_cloudfront_function" "participants_auth" {
  name    = "${local.name}-participants-auth"
  runtime = "cloudfront-js-2.0"
  comment = "Basic auth for /participants* on the handson guide"
  publish = true
  code = templatefile("${path.module}/templates/participants-auth.js.tftpl", {
    expected = "Basic ${base64encode("${var.participants_user}:${var.participants_password}")}"
  })
}
