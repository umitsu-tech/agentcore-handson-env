# 複数のファイルから参照するデータソースはここに置く（iam.tf と ec2.tf の user_data が使う）
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.project_name

  # ALB は 2 AZ 以上のサブネットを要求するので必ず 2 つ用意する
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 受講者ごとのサブドメイン。userNN.<base_domain> でアクセスする
  participants = {
    for p in var.participants : p => {
      hostname = "${p}.${var.base_domain}"
    }
  }
}
