output "participant_urls" {
  description = "受講者に配る URL。ブラウザで開いてパスワードを入れると code-server が使える"
  value       = { for k, v in local.participants : k => "https://${v.hostname}" }
}

output "participant_ui_urls" {
  description = "受講者に配るハンズオン UI の URL。code-server にログイン済みのブラウザで開く"
  value       = { for k, v in local.participants : k => "https://${v.hostname}/proxy/3000/" }
}

output "participant_passwords" {
  description = "受講者ごとの code-server のパスワード"
  value       = { for k, v in random_password.code_server : k => v.result }
  sensitive   = true
}

output "alb_dns_name" {
  description = "ALB の DNS 名。*.<base_domain> の CNAME は Terraform が向けるので手作業は不要。Cloudflare 側の値と突き合わせるときに見る"
  value       = aws_lb.this.dns_name
}

output "instance_ids" {
  description = "トラブル対応で Session Manager から入るときに使う"
  value       = { for k, v in aws_instance.participant : k => v.id }
}
