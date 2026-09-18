resource "aws_kms_replica_key" "this" {
  count = var.replica_key.create && var.multi_region ? 1 : 0

  provider = aws.replica

  description             = "KMS Replica Key for ${local.rendered_description_name} in ${var.environment}"
  primary_key_arn         = aws_kms_key.this.arn
  deletion_window_in_days = var.replica_key.deletion_window_in_days

  policy = var.replica_key.policy_json != null ? var.replica_key.policy_json : var.policy_json

  bypass_policy_lockout_safety_check = false

  tags = local.tags
}

resource "aws_kms_alias" "replica" {
  count    = var.replica_key.create && var.multi_region ? 1 : 0
  provider = aws.replica

  name          = "alias/${local.rendered_name}-replica-key"
  target_key_id = aws_kms_replica_key.this[0].key_id
}
