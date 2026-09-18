resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  ingress = []
  egress  = []

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-default-deny-all"
  })
}
