data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "deployer_assume_role" {
  count = var.create_deployer_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = var.deployer_principal_arn_patterns
    }
  }
}

resource "aws_iam_role" "deployer" {
  count = var.create_deployer_role ? 1 : 0

  name               = coalesce(var.deployer_role_name, "${local.rendered_name}-deployer")
  description        = "Deploys ${local.rendered_name} code without infrastructure permissions"
  assume_role_policy = data.aws_iam_policy_document.deployer_assume_role[0].json
  tags               = local.tags

  lifecycle {
    precondition {
      condition     = length(var.deployer_principal_arn_patterns) > 0
      error_message = "deployer_principal_arn_patterns must be set when create_deployer_role is true."
    }

    precondition {
      condition     = var.artifact_bucket_arn != null
      error_message = "artifact_bucket_arn must be set when create_deployer_role is true."
    }
  }
}

data "aws_iam_policy_document" "deployer" {
  count = var.create_deployer_role ? 1 : 0

  statement {
    sid       = "ReadArtifactBucketLocation"
    actions   = ["s3:GetBucketLocation"]
    resources = [coalesce(var.artifact_bucket_arn, "arn:${data.aws_partition.current.partition}:s3:::invalid")]
  }

  statement {
    sid       = "ListFunctionArtifacts"
    actions   = ["s3:ListBucket"]
    resources = [coalesce(var.artifact_bucket_arn, "arn:${data.aws_partition.current.partition}:s3:::invalid")]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.artifact_prefix}/*"]
    }
  }

  statement {
    sid = "ManageFunctionArtifacts"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${coalesce(var.artifact_bucket_arn, "arn:${data.aws_partition.current.partition}:s3:::invalid")}/${local.artifact_prefix}/*"]
  }

  statement {
    sid = "DeployAndInvokeFunction"
    actions = [
      "lambda:DeleteFunction",
      "lambda:GetAlias",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:InvokeFunction",
      "lambda:PublishVersion",
      "lambda:UpdateAlias",
      "lambda:UpdateFunctionCode"
    ]
    resources = [
      aws_lambda_function.this.arn,
      "${aws_lambda_function.this.arn}:*"
    ]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid = "UseArtifactKmsKey"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "deployer" {
  count = var.create_deployer_role ? 1 : 0

  name        = coalesce(var.deployer_role_name, "${local.rendered_name}-deployer")
  description = "Least-privilege deployment permissions for ${local.rendered_name}"
  policy      = data.aws_iam_policy_document.deployer[0].json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "deployer" {
  count = var.create_deployer_role ? 1 : 0

  role       = aws_iam_role.deployer[0].name
  policy_arn = aws_iam_policy.deployer[0].arn
}
