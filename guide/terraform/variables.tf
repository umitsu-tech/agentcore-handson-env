variable "project_name" {
  description = "リソース名の接頭辞。受講環境と区別できるように -guide を付けている"
  type        = string
  default     = "agentcore-handson-guide"
}

variable "region" {
  description = "S3 バケットを置くリージョン。CloudFront はグローバルなのでどこでもよい"
  type        = string
  default     = "ap-northeast-1"
}

variable "guide_hostname" {
  description = "手順書に付ける独自ドメイン（例: guide.handson.example.com）。null なら CloudFront の既定ドメイン（xxxx.cloudfront.net）だけで配信する"
  type        = string
  default     = null
}

variable "cloudflare_zone_id" {
  description = "guide_hostname を管理している Cloudflare ゾーンの ID。guide_hostname を指定するときだけ要る"
  type        = string
  default     = null
}
