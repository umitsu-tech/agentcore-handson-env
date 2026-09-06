resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Allow HTTPS from participants"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from participants"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP, redirected to HTTPS"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_instances" {
  security_group_id            = aws_security_group.alb.id
  description                  = "code-server on participant instances"
  referenced_security_group_id = aws_security_group.instance.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# インターネットから EC2 に直接届く経路は作らない。
# 入ってこられるのは ALB からの 8080 だけで、SSH も開けない。
# 管理者が入るときは Session Manager を使う（アウトバウンドだけで到達できる）。
resource "aws_security_group" "instance" {
  name        = "${local.name}-instance"
  description = "Allow code-server traffic from the ALB only"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-instance"
  }
}

resource "aws_vpc_security_group_ingress_rule" "instance_from_alb" {
  security_group_id            = aws_security_group.instance.id
  description                  = "code-server from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "instance_all" {
  security_group_id = aws_security_group.instance.id
  description       = "Package downloads, AWS API calls"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
