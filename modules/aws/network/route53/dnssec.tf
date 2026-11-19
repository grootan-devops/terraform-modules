module "dnssec_key" {
  source = "../../security/kms"
  count  = local.signing ? 1 : 0

  application             = var.application
  environment             = var.environment
  name                    = coalesce(var.name, "zone-${substr(md5(var.zone_name), 0, 8)}")
  purpose                 = "dnssec"
  tags                    = var.tags
  region                  = local.region
  description             = "${var.zone_name} DNSSEC key-signing key"
  key_usage               = "SIGN_VERIFY"
  key_spec                = "ECC_NIST_P256"
  deletion_window_in_days = var.dnssec.deletion_window_in_days
  policy_statements       = local.dnssec_key_statements
}

resource "aws_route53_key_signing_key" "this" {
  count = local.signing ? 1 : 0

  hosted_zone_id             = aws_route53_zone.this.id
  key_management_service_arn = module.dnssec_key[0].arn
  name                       = replace(local.base, "-", "_")
  status                     = "ACTIVE"
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count = local.signing ? 1 : 0

  hosted_zone_id = aws_route53_key_signing_key.this[0].hosted_zone_id
  signing_status = "SIGNING"
}
