resource "random_password" "code_server" {
  for_each = local.participants

  length  = 20
  special = false
}

resource "aws_instance" "participant" {
  for_each = local.participants

  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = values(aws_subnet.public)[0].id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/../scripts/setup-code-server.sh", {
    code_server_password = random_password.code_server[each.key].result
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  # user_data にパスワードを渡すので、メタデータは IMDSv2 必須にしておく
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name        = "${local.name}-${each.key}"
    Participant = each.key
  }
}
