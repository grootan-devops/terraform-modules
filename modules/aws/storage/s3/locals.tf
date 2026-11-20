locals {
  bucket_name = coalesce(var.bucket_name, module.naming.names.bucket)
  arn         = "arn:${module.naming.partition}:s3:::${local.bucket_name}"
  kms_key_arn = module.encryption.key_arn
  uses_kms    = var.kms.create || var.kms.key_id != null
  notify      = var.notifications.eventbridge || length(var.notifications.topics) + length(var.notifications.queues) + length(var.notifications.functions) > 0
  role_arn    = var.replication.iam_role.create ? one(module.replication_role[*].arn) : var.replication.iam_role.arn

  guard_statements = [
    {
      sid        = "DenyInsecureTransport"
      effect     = "Deny"
      actions    = ["s3:*"]
      resources  = [local.arn, "${local.arn}/*"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }]
    },
    {
      sid        = "DenyOutdatedTls"
      effect     = "Deny"
      actions    = ["s3:*"]
      resources  = [local.arn, "${local.arn}/*"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "NumericLessThan", variable = "s3:TlsVersion", values = ["1.2"] }]
    }
  ]

  lifecycle_rules = [for r in var.lifecycle_rules : merge(r, { predicates = (r.prefix == null ? 0 : 1) + length(r.tags) })]

  replica_key_arns = [for r in var.replication.rules : r.replica_kms_key_arn if r.replica_kms_key_arn != null]
  cross_account    = length([for r in var.replication.rules : r if r.destination_account_id != null]) > 0

  replication_statement_candidates = [
    {
      when = true
      statement = {
        Sid      = "ReadSourceBucket"
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [local.arn]
      }
    },
    {
      when = true
      statement = {
        Sid      = "ReadSourceObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging", "s3:GetObjectRetention", "s3:GetObjectLegalHold"]
        Resource = ["${local.arn}/*"]
      }
    },
    {
      when = true
      statement = {
        Sid      = "ReplicateToDestinations"
        Effect   = "Allow"
        Action   = concat(["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"], local.cross_account ? ["s3:ObjectOwnerOverrideToBucketOwner"] : [])
        Resource = distinct([for r in var.replication.rules : "${r.destination_bucket_arn}/*"])
      }
    },
    {
      when = local.uses_kms
      statement = {
        Sid      = "DecryptSource"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [local.kms_key_arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "s3.${module.naming.region}.${module.naming.dns_suffix}" }
          StringLike   = { "kms:EncryptionContext:aws:s3:arn" = [local.arn, "${local.arn}/*"] }
        }
      }
    },
    {
      when = local.uses_kms
      statement = {
        Sid      = "EncryptReplicas"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = local.replica_key_arns
      }
    }
  ]

  replication_statements = [for c in local.replication_statement_candidates : c.statement if c.when]
}
