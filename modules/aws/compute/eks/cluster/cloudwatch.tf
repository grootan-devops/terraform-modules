resource "aws_cloudwatch_log_group" "eks_cluster" {
  name                        = "/aws/eks/${local.name_prefix}/cluster"
  retention_in_days           = var.log_retention_in_days
  kms_key_id                  = var.kms_key_arn
  deletion_protection_enabled = true

  tags = local.tags
}
