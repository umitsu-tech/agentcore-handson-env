data "aws_availability_zones" "available" {
  state = "available"
}

# AMI が未指定のときは Amazon Linux 2023（ARM64）の最新版を使う。
# #5 で受講環境を焼いた AMI ができたら var.ami_id に渡す。
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name = var.project_name

  # ALB は 2 AZ 以上のサブネットを要求するので必ず 2 つ用意する
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  ami_id = coalesce(var.ami_id, nonsensitive(data.aws_ssm_parameter.al2023_arm64.value))

  # 受講者ごとのサブドメイン。userNN.<base_domain> でアクセスする
  participants = {
    for p in var.participants : p => {
      hostname = "${p}.${var.base_domain}"
    }
  }
}
