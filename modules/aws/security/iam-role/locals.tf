locals {
  role_name = coalesce(var.role_name, module.naming.names.role)

  trust_principals = merge(
    length(var.trust.services) > 0 ? { Service = var.trust.services } : {},
    length(var.trust.aws_principals) > 0 ? { AWS = var.trust.aws_principals } : {},
    length(var.trust.federated) > 0 ? { Federated = var.trust.federated } : {}
  )

  trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge(
      {
        Effect    = "Allow"
        Principal = local.trust_principals
        Action    = var.trust.actions
      },
      length(var.trust.conditions) == 0 ? {} : {
        Condition = {
          for test in distinct([for c in var.trust.conditions : c.test]) : test => {
            for c in var.trust.conditions : c.variable => c.values if c.test == test
          }
        }
      }
    )]
  })

  has_inline_policy = length(var.policy_statements) + length(var.policy_documents) > 0
}
