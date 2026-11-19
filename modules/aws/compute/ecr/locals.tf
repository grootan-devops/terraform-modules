locals {
  repository_name = module.naming.names.repository
  kms_key_arn     = module.encryption.key_arn
  kms_encrypted   = var.kms.create || var.kms.key_id != null
  policy_enabled  = length(var.pull_principal_arns) + length(var.policy_statements) > 0

  pull_statements = length(var.pull_principal_arns) == 0 ? [] : [{
    sid        = "CrossAccountPull"
    effect     = "Allow"
    actions    = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources  = [aws_ecr_repository.this.arn]
    principals = { AWS = var.pull_principal_arns }
    conditions = []
  }]

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.lifecycle_policy.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = var.lifecycle_policy.tag_patterns
          countType      = "imageCountMoreThan"
          countNumber    = var.lifecycle_policy.keep_tagged_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
