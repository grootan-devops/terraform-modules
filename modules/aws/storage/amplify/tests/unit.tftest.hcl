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

  mock_resource "aws_amplify_app" {
    defaults = {
      id             = "d1a2b3c4d5e6f7"
      arn            = "arn:aws:amplify:eu-west-1:123456789012:apps/d1a2b3c4d5e6f7"
      default_domain = "d1a2b3c4d5e6f7.amplifyapp.com"
    }
  }
}

variables {
  application = "portal"
  environment = "prod"
  name        = "web"
  tags        = { Team = "frontend" }
  branches    = { main = {} }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_amplify_app.this.name == "portal-prod-web" && aws_amplify_app.this.platform == "WEB" && aws_amplify_app.this.description == "portal-prod-web app"
    error_message = "The app is <application>-<environment>-<name>."
  }

  assert {
    condition     = strcontains(aws_amplify_app.this.custom_headers, "Strict-Transport-Security") && strcontains(aws_amplify_app.this.custom_headers, "nosniff") && strcontains(aws_amplify_app.this.custom_headers, "SAMEORIGIN")
    error_message = "Security headers are applied by default."
  }

  assert {
    condition     = aws_amplify_app.this.enable_basic_auth == false && aws_amplify_app.this.basic_auth_credentials == null
    error_message = "No basic auth by default."
  }

  assert {
    condition     = aws_amplify_branch.this["main"].enable_auto_build == false && aws_amplify_branch.this["main"].stage == "PRODUCTION" && length(aws_amplify_domain_association.this) == 0
    error_message = "Branches do not build on their own; no custom domain by default."
  }

  assert {
    condition     = aws_amplify_app.this.tags["Name"] == "portal-prod-web" && aws_amplify_app.this.tags["Team"] == "frontend" && aws_amplify_app.this.tags["ManagedBy"] == "Terraform" && aws_amplify_branch.this["main"].tags["Name"] == "portal-prod-web-main" && aws_amplify_branch.this["main"].tags["Application"] == "portal"
    error_message = "App and branches carry caller and governance tags (Amplify.1, Amplify.2)."
  }
}

run "name_defaults_to_application_and_environment" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_amplify_app.this.name == "portal-prod"
    error_message = "Without name the app is <application>-<environment>."
  }
}

run "branches_domains_and_outputs" {
  command = apply

  variables {
    branches = {
      main    = { framework = "React" }
      staging = { stage = "BETA" }
    }
    domain_associations = {
      "example.com" = {
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
        sub_domains = {
          app     = { branch_name = "main", prefix = "app" }
          staging = { branch_name = "staging", prefix = "staging" }
        }
      }
      "example.org" = { wait_for_verification = false, sub_domains = { root = { branch_name = "main", prefix = "" } } }
    }
    custom_rules = [{ source = "/<*>", target = "/index.html", status = "404-200" }]
  }

  assert {
    condition     = aws_amplify_domain_association.this["example.com"].certificate_settings[0].type == "CUSTOM" && aws_amplify_domain_association.this["example.org"].certificate_settings[0].type == "AMPLIFY_MANAGED" && aws_amplify_domain_association.this["example.org"].wait_for_verification == false
    error_message = "A certificate ARN means a custom certificate, else Amplify managed."
  }

  assert {
    condition     = aws_amplify_domain_association.this["example.com"].enable_auto_sub_domain == false && length(aws_amplify_domain_association.this["example.com"].sub_domain) == 2
    error_message = "Only the listed sub-domains are created."
  }

  assert {
    condition     = output.id == "d1a2b3c4d5e6f7" && output.arn == "arn:aws:amplify:eu-west-1:123456789012:apps/d1a2b3c4d5e6f7" && output.default_domain == "d1a2b3c4d5e6f7.amplifyapp.com" && output.branch_names == ["main", "staging"]
    error_message = "Outputs expose the app and its branches."
  }

  assert {
    condition     = keys(output.domain_dns_records) == ["example.com", "example.org"] && keys(output.domain_dns_records["example.com"].sub_domains) == ["app", "staging"]
    error_message = "DNS records are exported by domain."
  }

  assert {
    condition     = aws_amplify_app.this.custom_rule[0].status == "404-200" && aws_amplify_branch.this["main"].framework == "React" && aws_amplify_branch.this["staging"].stage == "BETA"
    error_message = "Rules and branch settings must apply."
  }
}

run "custom_and_unmanaged_headers" {
  command = plan

  variables {
    custom_headers = { yaml = "customHeaders:\n  - pattern: '**'\n    headers:\n      - key: 'Content-Security-Policy'\n        value: \"default-src 'self'\"\n" }
  }

  assert {
    condition     = strcontains(aws_amplify_app.this.custom_headers, "Content-Security-Policy") && !strcontains(aws_amplify_app.this.custom_headers, "SAMEORIGIN")
    error_message = "Caller YAML replaces the module headers."
  }
}

run "headers_off" {
  command = plan

  variables {
    custom_headers = { enabled = false }
  }

  assert {
    condition     = local.custom_headers == null
    error_message = "Headers off leaves them unmanaged."
  }
}

run "basic_auth" {
  command = plan

  variables {
    basic_auth = { enabled = true, username = "reviewer", password = sha1("amplify-basic-auth-fixture") }
  }

  assert {
    condition     = aws_amplify_app.this.enable_basic_auth && aws_amplify_app.this.basic_auth_credentials == base64encode("reviewer:${sha1("amplify-basic-auth-fixture")}")
    error_message = "basic_auth sets base64 credentials."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Web_App"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Portal"
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

run "rejects_no_branches" {
  command = plan

  variables {
    branches = {}
  }

  expect_failures = [var.branches]
}

run "rejects_invalid_stage" {
  command = plan

  variables {
    branches = { main = { stage = "LIVE" } }
  }

  expect_failures = [var.branches]
}

run "rejects_unknown_sub_domain_branch" {
  command = plan

  variables {
    domain_associations = { "example.com" = { sub_domains = { app = { branch_name = "develop", prefix = "app" } } } }
  }

  expect_failures = [var.domain_associations]
}

run "rejects_invalid_rule_status" {
  command = plan

  variables {
    custom_rules = [{ source = "/a", target = "/b", status = "307" }]
  }

  expect_failures = [var.custom_rules]
}

run "rejects_basic_auth_without_password" {
  command = plan

  variables {
    basic_auth = { enabled = true, username = "reviewer" }
  }

  expect_failures = [var.basic_auth]
}
