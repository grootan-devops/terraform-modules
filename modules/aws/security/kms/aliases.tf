resource "aws_kms_alias" "this" {
  name          = "alias/${local.rendered_name}-key"
  target_key_id = aws_kms_key.this.key_id
}
