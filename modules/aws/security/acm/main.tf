module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
}

resource "aws_acm_certificate" "this" {
  region                    = var.region
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  key_algorithm             = var.key_algorithm
  validation_method         = "DNS"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }

  tags = module.naming.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = var.validation.enabled ? local.validation_domains : toset([])

  zone_id         = var.validation.zone_id
  name            = local.validation_options[each.key][0].resource_record_name
  type            = local.validation_options[each.key][0].resource_record_type
  records         = [local.validation_options[each.key][0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = var.validation.enabled ? 1 : 0

  region                  = var.region
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
