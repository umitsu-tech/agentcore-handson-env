# ALB で TLS を終端すれば、証明書は ACM のワイルドカード 1 枚で受講者全員ぶんをまかなえる。
# EC2 側は HTTP のままでよく、証明書を人数ぶん配る必要がない。
resource "aws_lb" "this" {
  name               = local.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  idle_timeout = 300
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Unknown participant."
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# 受講者ごとにターゲットグループを作り、ホスト名で振り分ける。
# 人数が増えてもルールとターゲットグループが増えるだけで、ALB は 1 つのまま。
resource "aws_lb_target_group" "participant" {
  for_each = local.participants

  name     = "${local.name}-${each.key}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # code-server は WebSocket を使うので、同じセッションが同じインスタンスに
  # 戻るようにしておく。1 台構成でも将来の増設時に効く。
  stickiness {
    type    = "lb_cookie"
    enabled = true
  }
}

resource "aws_lb_target_group_attachment" "participant" {
  for_each = local.participants

  target_group_arn = aws_lb_target_group.participant[each.key].arn
  target_id        = aws_instance.participant[each.key].id
  port             = 8080
}

resource "aws_lb_listener_rule" "participant" {
  for_each = local.participants

  listener_arn = aws_lb_listener.https.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.participant[each.key].arn
  }

  condition {
    host_header {
      values = [each.value.hostname]
    }
  }
}
