terraform {
  # S3 バックエンドのロックに use_lockfile を使うため 1.10 以降が要る（DynamoDB を使わない）
  required_version = ">= 1.10"

  # state は scripts/build-ami.sh と同じ資材バケットの terraform-state/ に置く。
  # バケット名にアカウント ID が入るので、ここには書かず backend.hcl（git 管理外）で渡す。
  # 初回は `terraform init -backend-config=backend.hcl`（docs/operations.md）
  backend "s3" {
    key          = "terraform-state/agentcore-handson.tfstate"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# API トークンは環境変数 CLOUDFLARE_API_TOKEN から読む。tfvars には書かない
provider "cloudflare" {}
