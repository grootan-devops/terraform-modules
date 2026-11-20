locals {
  validation_domains = toset([for d in concat([var.domain_name], var.subject_alternative_names) : trimprefix(d, "*.")])

  validation_options = {
    for o in aws_acm_certificate.this.domain_validation_options : trimprefix(o.domain_name, "*.") => o...
  }

  certificate_arn = var.validation.enabled ? one(aws_acm_certificate_validation.this[*].certificate_arn) : aws_acm_certificate.this.arn
}
