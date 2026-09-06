output "guide_url" {
  description = "受講者に配る手順書の URL"
  value       = local.custom_domain ? "https://${var.guide_hostname}/" : "https://${aws_cloudfront_distribution.site.domain_name}/"
}

output "cloudfront_domain_name" {
  description = "CloudFront の既定ドメイン。独自ドメインを付けていてもこちらでも開ける"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "bucket_name" {
  description = "publish.sh が同期する先"
  value       = aws_s3_bucket.site.bucket
}

output "distribution_id" {
  description = "publish.sh がキャッシュ削除に使う"
  value       = aws_cloudfront_distribution.site.id
}

output "github_actions_role_arn" {
  description = "GitHub の Variables（AWS_ROLE_ARN）に登録するロール ARN。github_repository を指定していなければ null"
  value       = var.github_repository != null ? aws_iam_role.github_actions[0].arn : null
}

output "participants_url" {
  description = "受講者情報ページ。開くと Basic 認証を聞かれる（participants_user / participants_password）"
  value       = local.custom_domain ? "https://${var.guide_hostname}/participants.html" : "https://${aws_cloudfront_distribution.site.domain_name}/participants.html"
}
