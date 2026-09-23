resource "random_password" "code_server" {
  for_each = local.participants

  length  = 20
  special = false
}

resource "aws_instance" "participant" {
  for_each = local.participants

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[local.participant_az[each.key]].id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/templates/configure-instance.sh.tftpl", {
    code_server_password = random_password.code_server[each.key].result
    participant          = each.key
    account_id           = data.aws_caller_identity.current.account_id
    hostname             = local.participants[each.key].hostname
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
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
