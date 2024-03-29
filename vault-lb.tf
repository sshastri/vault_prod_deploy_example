data "aws_acm_certificate" "vault_alb" {
  domain   = "${local.acm_certificate_domain}"
  statuses = ["ISSUED"]
}

resource "aws_security_group" "vault_alb" {
  name        = "vault-alb"
  description = "Rules for Vault application load balancer"
  vpc_id      = "${data.terraform_remote_state.network.vpc_id}"

  ingress {
    description = "Ingress tcp/443 from anywhere"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ingress tcp/8200 from anywhere"
    protocol    = "tcp"
    from_port   = 8200
    to_port     = 8200

    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Egress tcp/8200 to Vault EC2 instances"
    protocol    = "tcp"
    from_port   = 8200
    to_port     = 8200

    security_groups = ["${module.vault.security_group_id}"]
  }
}

resource "aws_lb" "vault" {
  name            = "vault-${local.cluster_name}"
  internal        = true
  security_groups = ["${aws_security_group.vault_alb.id}"]
  subnets         = ["${data.terraform_remote_state.network.private_subnets}"]
}

# Name attribute must be 32 characters or less
resource "aws_lb_target_group" "vault_https_8200" {
  #name = "${format("vault-https-8200-%s", local.cluster_name)}"
  name  = "vault-https-8200-dev"

  vpc_id               = "${data.terraform_remote_state.network.vpc_id}"
  port                 = "8200"
  protocol             = "HTTPS"
  deregistration_delay = 60

  health_check {
    protocol            = "HTTPS"
    port                = 8200
    path                = "/v1/sys/health"
    matcher             = "200,473"
    interval            = 20
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 9
  }
}

resource "aws_autoscaling_attachment" "vault_asg_attachment" {
  autoscaling_group_name = "${module.vault.vault_autoscale_group_id}"
  alb_target_group_arn   = "${aws_lb_target_group.vault_https_8200.arn}"
}


resource "aws_lb_listener" "vault_https_443" {
  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  #certificate_arn   = "${data.aws_acm_certificate.vault_lb.arn}"
  certificate_arn   = "${aws_iam_server_certificate.vault_certificate.arn}"

  default_action {
    target_group_arn = "${aws_lb_target_group.vault_https_8200.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "vault_https_8200" {
  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = "8200"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  #certificate_arn   = "${data.aws_acm_certificate.vault_lb.arn}"
  certificate_arn   = "${aws_iam_server_certificate.vault_certificate.arn}"

  default_action {
    target_group_arn = "${aws_lb_target_group.vault_https_8200.arn}"
    type             = "forward"
  }
}

data "aws_route53_zone" "hashi" {
  name         = "hashi-demos.com."
  private_zone = false
}

resource "aws_route53_record" "hashi" {
  zone_id = "${data.aws_route53_zone.hashi.zone_id}"
  name    = "${local.hostname}.${data.aws_route53_zone.hashi.name}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${aws_lb.vault.dns_name}"]
}


resource "tls_private_key" "vault_tls" {
  algorithm = "ECDSA"
}

resource "tls_self_signed_cert" "vault_tls" {
  key_algorithm   = "${tls_private_key.vault_tls.algorithm}"
  private_key_pem = "${tls_private_key.vault_tls.private_key_pem}"

  # Certificate expires after 72 hours.
  validity_period_hours = 72

  # Generate a new certificate if Terraform is run within three
  # hours of the certificate's expiration time.
  early_renewal_hours = 3

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
      "key_encipherment",
      "digital_signature",
      "server_auth",
  ]

  dns_names = ["vault-dev-us-1.hashi-demos.com"]

  subject {
      common_name  = "hashi-demos.com"
      organization = "ACME Examples, Inc"
  }
}

# For example, this can be used to populate an AWS IAM server certificate.
resource "aws_iam_server_certificate" "vault_certificate" {
  name             = "vault-dev-01"
  certificate_body = "${tls_self_signed_cert.vault_tls.cert_pem}"
  private_key      = "${tls_private_key.vault_tls.private_key_pem}"
}
