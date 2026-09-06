# 受講者向けの手順書（HTML）を S3 + CloudFront で配信する。
# S3 は非公開にして、CloudFront だけが OAC（Origin Access Control）で読めるようにする。
# 中身の更新は Terraform ではなく ../../guide/publish.sh（s3 sync + キャッシュ削除）で行う。

data "aws_caller_identity" "current" {}

locals {
  name          = var.project_name
  origin_id     = "s3-${local.name}"
  custom_domain = var.guide_hostname != null
}

# --- S3 ------------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = "${local.name}-${data.aws_caller_identity.current.account_id}"

  # destroy のときに中身ごと消す。手順書の原本は git にあるので失っても困らない
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# CloudFront（このディストリビューション）からの GetObject だけ許可する
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# --- CloudFront ---------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = local.name
  description                       = "handson guide (S3 private origin)"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "AgentCore handson guide"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 日本を含む。受講者は国内なので All は要らない
  aliases             = local.custom_domain ? [var.guide_hostname] : []

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
    origin_id                = local.origin_id
  }

  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # 受講者情報（participants.html と participants/data.json）だけ Basic 認証を挟む。
  # 関数は viewer-request で毎回動くので、キャッシュに乗っていても認証は通らない
  ordered_cache_behavior {
    path_pattern           = "/participants*"
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.participants_auth.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 独自ドメインを付けるときは us-east-1 の ACM 証明書、付けないときは CloudFront の既定証明書
  viewer_certificate {
    cloudfront_default_certificate = local.custom_domain ? null : true
    acm_certificate_arn            = local.custom_domain ? aws_acm_certificate_validation.guide[0].certificate_arn : null
    ssl_support_method             = local.custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.custom_domain ? "TLSv1.2_2021" : null
  }
}

# --- 独自ドメイン（guide_hostname を指定したときだけ） ---------------------------------
# 証明書は guide_hostname 単体で取る。受講環境のワイルドカード証明書（ap-northeast-1）とは
# 検証用 CNAME の名前が変わるので、Cloudflare 側でぶつからない。

resource "aws_acm_certificate" "guide" {
  count    = local.custom_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.guide_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "guide_validation" {
  for_each = local.custom_domain ? {
    for dvo in aws_acm_certificate.guide[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.name, ".")
  type    = each.value.type
  content = trimsuffix(each.value.value, ".")
  ttl     = 1
  proxied = false
  comment = "ACM validation for handson guide (managed by terraform)"
}

resource "aws_acm_certificate_validation" "guide" {
  count    = local.custom_domain ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.guide[0].arn
  validation_record_fqdns = [for r in cloudflare_dns_record.guide_validation : r.name]
}

# 受講者が開く名前を CloudFront に向ける（DNS only）
resource "cloudflare_dns_record" "guide" {
  count = local.custom_domain ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.guide_hostname
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  ttl     = 1
  proxied = false
  comment = "AgentCore handson guide: managed by terraform"
}
