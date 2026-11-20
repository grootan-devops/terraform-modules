resource "aws_kms_replica_key" "this" {
  for_each = toset(var.replica_regions)

  region                             = each.key
  description                        = local.description
  primary_key_arn                    = aws_kms_key.this.arn
  deletion_window_in_days            = var.deletion_window_in_days
  policy                             = module.policy.json
  bypass_policy_lockout_safety_check = false

  tags = module.naming.tags
}

resource "aws_kms_alias" "replica" {
  for_each = toset(var.replica_regions)

  region        = each.key
  name          = local.alias
  target_key_id = aws_kms_replica_key.this[each.key].key_id
}
