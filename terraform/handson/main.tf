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

  # 受講者の EC2 を置く AZ。1 つの AZ で t4g.small の在庫が足りないときに全員が止まらないよう、
  # 名前の末尾の番号（userNN の NN）の偶数・奇数で 2 つの AZ に振り分ける。並び順の何番目かで決めると、
  # 途中の受講者を外しただけでそれ以降の全員の AZ が変わり、EC2 が作り直しになるため。
  # 数字で終わらない名前はハッシュで決める（Issue #83）
  participant_az = {
    for p in var.participants : p => local.azs[
      can(regex("[0-9]+$", p))
      ? tonumber(regex("[0-9]+$", p)) % length(local.azs)
      : parseint(substr(md5(p), 0, 8), 16) % length(local.azs)
    ]
  }
}
