mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "frontend"
  branches    = ["main"]
}

run "verify_naming" {
  command = plan

  assert {
    condition     = aws_amplify_app.this.name == "core-prod-frontend"
    error_message = "Amplify app name must render as <application>-<environment>-<name>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_amplify_app.this.name == "core-prod"
    error_message = "Amplify app name must fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_amplify_app.this.tags["Name"] == "core-prod"
    error_message = "Amplify app Name tag must fall back to <application>-<environment> when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_amplify_app.this.name == "core-prod"
    error_message = "Amplify app name must fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    branches = ["main", "staging"]
    tags = {
      FrontEndTier = "SinglePageApp"
      CostCenter   = "1234"
    }
  }

  assert {
    condition     = aws_amplify_app.this.tags["Application"] == "core" && aws_amplify_app.this.tags["Environment"] == "prod" && aws_amplify_app.this.tags["Name"] == "core-prod-frontend"
    error_message = "Amplify app must carry Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_amplify_app.this.tags["FrontEndTier"] == "SinglePageApp" && aws_amplify_app.this.tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the Amplify app."
  }

  assert {
    condition     = alltrue([for b in aws_amplify_branch.this : b.tags["Application"] == "core" && b.tags["Environment"] == "prod" && b.tags["FrontEndTier"] == "SinglePageApp"])
    error_message = "Branches must carry governance and caller tags."
  }

  assert {
    condition     = aws_amplify_branch.this["main"].tags["Name"] == "main" && aws_amplify_branch.this["staging"].tags["Name"] == "staging"
    error_message = "Branches must override the Name tag with the branch name."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_amplify_app.this.platform == "WEB"
    error_message = "Amplify app must be a static WEB platform app."
  }

  assert {
    condition     = aws_amplify_app.this.enable_basic_auth == false
    error_message = "Basic auth must be disabled by default."
  }

  assert {
    condition     = aws_amplify_app.this.basic_auth_credentials == null
    error_message = "No basic auth credentials must be set when basic auth is disabled."
  }

  assert {
    condition     = aws_amplify_branch.this["main"].enable_auto_build == false
    error_message = "Branch auto build must be disabled."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = length(aws_amplify_branch.this) == 1 && aws_amplify_branch.this["main"].branch_name == "main"
    error_message = "One branch must be created per entry in branches."
  }

  assert {
    condition     = length(aws_amplify_domain_association.this) == 0
    error_message = "No domain associations must be created by default."
  }

  assert {
    condition     = length(aws_amplify_app.this.custom_rule) == 0
    error_message = "No custom rules must be configured by default."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    branches = ["main", "staging"]
    basic_auth = {
      enable   = true
      username = "reviewer"
      password = sha256("amplify-test-fixture")
    }
    custom_headers = "customHeaders:\n  - pattern: '**/*'\n    headers:\n      - key: Strict-Transport-Security\n        value: max-age=31536000\n"
    custom_rules = [
      {
        source = "/<*>"
        target = "/index.html"
        status = "404-200"
      },
      {
        source    = "/docs"
        target    = "https://docs.example.com"
        status    = "302"
        condition = "<US>"
      },
    ]
  }

  assert {
    condition     = length(aws_amplify_branch.this) == 2 && aws_amplify_branch.this["staging"].branch_name == "staging"
    error_message = "One branch must be created per entry in branches."
  }

  assert {
    condition     = aws_amplify_app.this.enable_basic_auth == true
    error_message = "basic_auth.enable must enable basic auth on the app."
  }

  assert {
    condition     = aws_amplify_app.this.basic_auth_credentials == base64encode("reviewer:${sha256("amplify-test-fixture")}")
    error_message = "Basic auth credentials must be the base64-encoded username:password pair."
  }

  assert {
    condition     = aws_amplify_app.this.custom_headers == var.custom_headers
    error_message = "custom_headers must flow through to the app."
  }

  assert {
    condition     = length(aws_amplify_app.this.custom_rule) == 2
    error_message = "One custom rule must be rendered per entry in custom_rules."
  }

  assert {
    condition     = aws_amplify_app.this.custom_rule[0].source == "/<*>" && aws_amplify_app.this.custom_rule[0].target == "/index.html" && aws_amplify_app.this.custom_rule[0].status == "404-200"
    error_message = "Custom rule source, target and status must flow through."
  }

  assert {
    condition     = aws_amplify_app.this.custom_rule[1].condition == "<US>" && aws_amplify_app.this.custom_rule[1].status == "302"
    error_message = "Custom rule condition must flow through."
  }
}

run "verify_domain_associations" {
  command = plan

  variables {
    branches = ["main", "staging"]
    domain_associations = {
      "example.com" = {
        sub_domains = {
          app = {
            branch_name = "main"
            prefix      = "app"
          }
          staging = {
            branch_name = "staging"
            prefix      = "staging-app"
          }
        }
      }
      "portal.example.com" = {
        acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        sub_domains = {
          root = {
            branch_name = "main"
            prefix      = ""
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_amplify_domain_association.this) == 2
    error_message = "One domain association must be created per entry in domain_associations."
  }

  assert {
    condition     = aws_amplify_domain_association.this["example.com"].domain_name == "example.com"
    error_message = "Domain association must use the map key as the domain name."
  }

  assert {
    condition     = alltrue([for d in aws_amplify_domain_association.this : d.enable_auto_sub_domain == false && d.wait_for_verification == true])
    error_message = "Domain associations must disable automatic sub-domains and wait for verification."
  }

  assert {
    condition     = aws_amplify_domain_association.this["example.com"].certificate_settings[0].type == "AMPLIFY_MANAGED" && aws_amplify_domain_association.this["example.com"].certificate_settings[0].custom_certificate_arn == null
    error_message = "Domain association must use an Amplify-managed certificate when no ACM certificate is supplied."
  }

  assert {
    condition     = aws_amplify_domain_association.this["portal.example.com"].certificate_settings[0].type == "CUSTOM"
    error_message = "Domain association must use a CUSTOM certificate when an ACM certificate is supplied."
  }

  assert {
    condition     = aws_amplify_domain_association.this["portal.example.com"].certificate_settings[0].custom_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    error_message = "Domain association must use the supplied ACM certificate ARN."
  }

  assert {
    condition     = toset([for s in aws_amplify_domain_association.this["example.com"].sub_domain : "${s.prefix}=${s.branch_name}"]) == toset(["app=main", "staging-app=staging"])
    error_message = "Sub-domains must map each prefix to its branch."
  }

  assert {
    condition     = toset([for s in aws_amplify_domain_association.this["portal.example.com"].sub_domain : "${s.prefix}=${s.branch_name}"]) == toset(["=main"])
    error_message = "Apex sub-domain must map to its branch."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
