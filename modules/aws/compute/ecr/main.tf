module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    repository = { max_length = 63 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application = var.application
  environment = var.environment
  name        = var.name
  purpose     = "ecr"
  tags        = var.tags
  kms         = var.kms
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = [aws_ecr_repository.this.arn]
  statements        = concat(local.pull_statements, var.policy_statements)
}

#trivy:ignore:AVD-AWS-0033
resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = var.image_tag_mutability_exclusion_filters
    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = local.kms_encrypted ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn
  }

  tags = merge(module.naming.tags, { Name = local.repository_name })
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.lifecycle_policy.enabled ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

resource "aws_ecr_repository_policy" "this" {
  count = local.policy_enabled ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = module.policy.json
}
