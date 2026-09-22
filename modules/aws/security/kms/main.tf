resource "aws_kms_key" "this" {
  description              = var.description != null ? var.description : "KMS Key for ${local.rendered_description_name} in ${var.environment}"
  is_enabled               = var.is_enabled
  key_usage                = var.key_usage
  customer_master_key_spec = var.customer_master_key_spec
  deletion_window_in_days  = var.deletion_window_in_days
  enable_key_rotation      = var.enable_key_rotation
  rotation_period_in_days  = var.rotation_period_in_days
  multi_region             = var.multi_region

  bypass_policy_lockout_safety_check = false

  tags = local.tags
}

resource "aws_kms_key_policy" "this" {
  count = var.policy_json != null ? 1 : 0

  key_id = aws_kms_key.this.id
  policy = var.policy_json

  bypass_policy_lockout_safety_check = false
}
