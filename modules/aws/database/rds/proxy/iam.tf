data "aws_iam_policy_document" "rds_proxy_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "${local.rendered_name}-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json

  tags = merge(local.tags, { Name = "${local.rendered_name}-proxy-role" })
}

locals {
  secret_arns = compact([for auth in var.auth_blocks : lookup(auth, "secret_arn", null)])
}

data "aws_iam_policy_document" "rds_proxy_secrets" {
  count = length(var.auth_blocks) > 0 ? 1 : 0

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = local.secret_arns
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []
    content {
      actions = [
        "kms:Decrypt"
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  count  = length(var.auth_blocks) > 0 ? 1 : 0
  name   = "${local.rendered_name}-proxy-secrets-policy"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy_secrets[0].json
}
