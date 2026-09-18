resource "aws_iam_role" "replication" {
  count = var.replication_configuration != null && try(var.replication_configuration.role, null) == null ? 1 : 0

  name = "${local.rendered_name}-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_policy" "replication" {
  count = var.replication_configuration != null && try(var.replication_configuration.role, null) == null ? 1 : 0

  name        = "${local.rendered_name}-replication-policy"
  description = "Policy for S3 replication"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Action = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket"
          ]
          Effect   = "Allow"
          Resource = [aws_s3_bucket.this.arn]
        },
        {
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging"
          ]
          Effect   = "Allow"
          Resource = ["${aws_s3_bucket.this.arn}/*"]
        },
        {
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags"
          ]
          Effect   = "Allow"
          Resource = [for rule in var.replication_configuration.rules : "${rule.destination.bucket}/*"]
        }
      ],
      var.kms_key_arn != null ? [
        {
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey"
          ]
          Effect   = "Allow"
          Resource = [var.kms_key_arn]
        }
      ] : [],
      length(compact([for rule in var.replication_configuration.rules : try(rule.destination.encryption_configuration.replica_kms_key_id, "")])) > 0 ? [
        {
          Action = [
            "kms:Encrypt",
            "kms:GenerateDataKey"
          ]
          Effect   = "Allow"
          Resource = compact([for rule in var.replication_configuration.rules : try(rule.destination.encryption_configuration.replica_kms_key_id, "")])
        }
      ] : []
    )
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "replication" {
  count      = var.replication_configuration != null && try(var.replication_configuration.role, null) == null ? 1 : 0
  role       = aws_iam_role.replication[0].name
  policy_arn = aws_iam_policy.replication[0].arn
}
