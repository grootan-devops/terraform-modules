resource "aws_ecr_registry_scanning_configuration" "this" {
  for_each = local.per_region.ecr_scanning

  region    = each.key
  scan_type = var.ecr_registry_scanning.type

  dynamic "rule" {
    for_each = var.ecr_registry_scanning.rules

    content {
      scan_frequency = rule.value.scan_frequency

      dynamic "repository_filter" {
        for_each = rule.value.filters

        content {
          filter      = repository_filter.value
          filter_type = "WILDCARD"
        }
      }
    }
  }
}

resource "aws_ecr_replication_configuration" "this" {
  for_each = local.ecr_replication

  region = each.key

  replication_configuration {
    dynamic "rule" {
      for_each = each.value

      content {
        dynamic "destination" {
          for_each = rule.value.destinations

          content {
            region      = destination.value.region
            registry_id = destination.value.registry_id
          }
        }

        dynamic "repository_filter" {
          for_each = rule.value.repository_prefixes

          content {
            filter      = repository_filter.value
            filter_type = "PREFIX_MATCH"
          }
        }
      }
    }
  }
}

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.ecr_pull_through_cache_rules

  region                     = each.value.region
  ecr_repository_prefix      = each.value.prefix
  upstream_registry_url      = each.value.rule.upstream_registry_url
  upstream_repository_prefix = each.value.rule.upstream_repository_prefix
  credential_arn             = each.value.rule.credential_arn
  custom_role_arn            = each.value.rule.custom_role_arn
}
