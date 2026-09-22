# *.<base_domain> の CNAME を ALB に向ける。ALB は destroy と apply のたびに DNS 名が変わるので、
# Terraform に持たせて自動で追随させる。ワイルドカードを 1 件作れば受講者が増えてもレコードは増えない。
# 証明書の検証用 CNAME は一度作ればそのままなので、ここでは扱わない。
resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  # v5 のプロバイダーは name をゾーン名まで含めた完全な形で受け取る。相対名だと plan のたびに差分が出る
  name    = "*.${var.base_domain}"
  type    = "CNAME"
  content = aws_lb.this.dns_name
  ttl     = 1 # 1 は Cloudflare の automatic
  # プロキシを通すと 2 階層のサブドメイン（user01.handson.example.com）が Universal SSL の範囲外になるため、DNS only にする。TLS は ALB の ACM 証明書で終端する
  proxied = false
  comment = "AgentCore handson: managed by terraform"
}
