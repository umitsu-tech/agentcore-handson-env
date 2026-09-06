terraform {
  # 受講環境（../handson）と同じく S3 バックエンド + use_lockfile。1.10 以降が要る
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
  }

  # state は受講環境と同じ資材バケットに置き、キーだけ分ける。
  # バケット名は backend.hcl（git 管理外）で渡す。`terraform init -backend-config=backend.hcl`
  backend "s3" {
    key          = "terraform-state/agentcore-handson-guide.tfstate"
    use_lockfile = true
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

# CloudFront に付ける ACM 証明書は us-east-1 でしか発行できない
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# API トークンは環境変数 CLOUDFLARE_API_TOKEN から読む（受講環境と同じトークンでよい）
provider "cloudflare" {}
