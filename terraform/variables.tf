variable "project_name" {
  description = "リソース名の接頭辞に使う"
  type        = string
  default     = "agentcore-handson"
}

variable "region" {
  description = "AgentCore と Bedrock が使えるリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "participants" {
  description = "受講者の識別子。ここに並べたぶんだけ EC2 とサブドメインができる。まずは 1 人で通す"
  type        = list(string)
  default     = ["user01"]

  validation {
    condition     = length(var.participants) > 0
    error_message = "participants は 1 つ以上必要です。"
  }
}

variable "base_domain" {
  description = "受講者ごとのサブドメインを生やす親ドメイン（例: handson.example.com）。userNN.<base_domain> でアクセスする"
  type        = string
}

variable "certificate_arn" {
  description = "ALB に付ける ACM 証明書の ARN。*.<base_domain> のワイルドカード証明書を事前に発行しておく"
  type        = string
}

variable "instance_type" {
  description = "AgentCore Runtime に合わせて ARM64 のインスタンスを使う。t4g.small と t4g.medium で agentcore deploy を実測して差が無かったので small（Issue #15）"
  type        = string
  default     = "t4g.small"
}

variable "ami_id" {
  description = "受講環境を焼いた AMI の ID（scripts/build-ami.sh で作る）"
  type        = string
}

variable "root_volume_size" {
  description = "ルートボリュームのサイズ（GiB）。AMI のルートボリューム（15GiB）以上にする。使用量は 5GB 弱（Issue #15）"
  type        = number
  default     = 15
}

variable "allowed_cidr_blocks" {
  description = "ALB に到達できる送信元。会場の固定 IP が分かっているなら絞る"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpc_cidr" {
  description = "VPC の CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "model_inference_profile" {
  description = "エージェントが呼ぶモデル。東京は In-Region 非対応なので推論プロファイルを指定する"
  type        = string
  default     = "jp.amazon.nova-2-lite-v1:0"
}

variable "cloudflare_zone_id" {
  description = "base_domain を管理している Cloudflare ゾーンの ID。*.<base_domain> の CNAME をこのゾーンに作る。ゾーンの概要ページに表示される 32 桁の値で、秘密ではない"
  type        = string
}

variable "handson_end_time" {
  description = "ハンズオンの終了時刻（RFC3339、例: 2026-10-31T17:00:00+09:00）。指定すると、この時刻を過ぎたら受講者ロールから Bedrock と Runtime の呼び出しを Deny し、EventBridge Scheduler が EC2 を停止して ALB を削除する。null なら仕組みごと作らない（検証用）"
  type        = string
  default     = null

  validation {
    condition     = var.handson_end_time == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(Z|[+-]\\d{2}:\\d{2})$", var.handson_end_time))
    error_message = "handson_end_time は 2026-10-31T17:00:00+09:00 のように秒とオフセットまで書いてください。"
  }
}

variable "handson_timezone" {
  description = "handson_end_time のオフセットに対応する IANA タイムゾーン名。EventBridge Scheduler の at() 式に使う。handson_end_time の +09:00 と食い違わせないこと"
  type        = string
  default     = "Asia/Tokyo"
}
