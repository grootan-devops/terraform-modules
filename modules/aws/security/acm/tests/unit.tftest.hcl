mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn    = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      status = "PENDING_VALIDATION"
      domain_validation_options = [
        { domain_name = "example.com", resource_record_name = "_a1.example.com.", resource_record_type = "CNAME", resource_record_value = "_b1.acm-validations.aws." },
        { domain_name = "*.example.com", resource_record_name = "_a1.example.com.", resource_record_type = "CNAME", resource_record_value = "_b1.acm-validations.aws." },
        { domain_name = "api.example.org", resource_record_name = "_a2.api.example.org.", resource_record_type = "CNAME", resource_record_value = "_b2.acm-validations.aws." }
      ]
    }
  }

  mock_resource "aws_route53_record" {
    defaults = {
      fqdn = "_a1.example.com"
    }
  }
}

variables {
  application               = "core"
  environment               = "prod"
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com", "api.example.org"]
  validation                = { zone_id = "Z0123456789ABCDEFGHIJ" }
  tags                      = { Team = "edge" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.domain_name == "example.com" && aws_acm_certificate.this.validation_method == "DNS" && aws_acm_certificate.this.key_algorithm == "RSA_2048"
    error_message = "DNS-validated RSA 2048 certificate by default (ACM.1, ACM.2)."
  }

  assert {
    condition     = aws_acm_certificate.this.options[0].certificate_transparency_logging_preference == "ENABLED"
    error_message = "Certificate transparency logging stays on."
  }

  assert {
    condition     = keys(aws_route53_record.validation) == ["api.example.org", "example.com"] && length(aws_acm_certificate_validation.this) == 1
    error_message = "One validation record per distinct name; a wildcard shares its base name's record."
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Name"] == "core-prod" && aws_acm_certificate.this.tags["Team"] == "edge" && aws_acm_certificate.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied (ACM.3)."
  }
}

run "dns_validation" {
  command = apply

  assert {
    condition     = aws_route53_record.validation["example.com"].name == "_a1.example.com." && aws_route53_record.validation["example.com"].type == "CNAME" && aws_route53_record.validation["example.com"].records == toset(["_b1.acm-validations.aws."]) && aws_route53_record.validation["api.example.org"].records == toset(["_b2.acm-validations.aws."])
    error_message = "Validation records come from the certificate's validation options."
  }

  assert {
    condition     = aws_route53_record.validation["example.com"].zone_id == "Z0123456789ABCDEFGHIJ" && aws_route53_record.validation["example.com"].allow_overwrite
    error_message = "Records go to validation.zone_id and survive certificate replacement."
  }

  assert {
    condition     = output.arn == "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555" && aws_acm_certificate_validation.this[0].certificate_arn == output.arn && output.validation_record_fqdns == ["_a1.example.com", "_a1.example.com"]
    error_message = "The ARN output waits for validation."
  }

  assert {
    condition     = output.status == "PENDING_VALIDATION" && output.domain_name == "example.com"
    error_message = "Status and domain name are exported."
  }
}

run "cloudfront_certificate" {
  command = plan

  variables {
    region        = "us-east-1"
    key_algorithm = "EC_prime256v1"
  }

  assert {
    condition     = aws_acm_certificate.this.region == "us-east-1" && aws_acm_certificate_validation.this[0].region == "us-east-1" && aws_acm_certificate.this.key_algorithm == "EC_prime256v1"
    error_message = "region places the certificate and its validation in us-east-1."
  }
}

run "external_validation" {
  command   = apply
  state_key = "external"

  variables {
    validation = { enabled = false }
  }

  assert {
    condition     = length(aws_route53_record.validation) == 0 && length(aws_acm_certificate_validation.this) == 0 && output.arn == aws_acm_certificate.this.arn
    error_message = "validation.enabled = false creates no records and returns the certificate ARN."
  }

  assert {
    condition     = length(output.validation_records) == 3 && output.validation_records[0].type == "CNAME"
    error_message = "Validation records are exported for external DNS."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Web_Cert"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_domain" {
  command = plan

  variables {
    domain_name = "Example.com."
  }

  expect_failures = [var.domain_name]
}

run "rejects_invalid_san" {
  command = plan

  variables {
    subject_alternative_names = ["api..example.com"]
  }

  expect_failures = [var.subject_alternative_names]
}

run "rejects_weak_key" {
  command = plan

  variables {
    key_algorithm = "RSA_1024"
  }

  expect_failures = [var.key_algorithm]
}

run "rejects_validation_without_zone" {
  command = plan

  variables {
    validation = {}
  }

  expect_failures = [var.validation]
}
