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
}

override_resource {
  target          = module.edge_key.module.key[0].aws_kms_key.this
  override_during = plan
  values = {
    arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
}

run "plans_with_unknown_ids" {
  command = plan

  assert {
    condition     = output.site_bucket == "storefront-dev-site-123456789012-eu-west-1" && output.log_bucket == "storefront-dev-logs-123456789012-eu-west-1"
    error_message = "Site and log buckets carry the account and Region and never share a name."
  }

  assert {
    condition     = output.web_acl_name == "storefront-dev-edge" && output.admin_app_name == "storefront-dev-admin"
    error_message = "The web ACL and the Amplify app follow the naming standard."
  }

  assert {
    condition     = output.edge_log_groups == ["/aws/cloudfront/storefront-dev-site", "aws-waf-logs-storefront-dev-edge"]
    error_message = "CloudFront and WAF log to their own us-east-1 log groups."
  }

  assert {
    condition     = module.edge_key.created && module.cdn.kms_key_arn == module.edge_key.key_arn && module.edge_waf.kms_key_arn == module.edge_key.key_arn
    error_message = "One us-east-1 stack key encrypts both edge log groups."
  }

  assert {
    condition     = startswith(module.edge_key.key_arn, "arn:aws:kms:us-east-1:")
    error_message = "The edge log key lives in us-east-1."
  }

  assert {
    condition     = keys(module.zone.record_fqdns) == ["admin", "apex", "apex-ipv6", "www", "www-ipv6"] && module.admin.branch_names == ["main"]
    error_message = "Apex and www alias the distribution; admin points at the Amplify branch."
  }
}
