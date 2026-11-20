module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    query_log_policy = { suffix = "route53-${local.zone_label}", max_length = 255 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "route53"
  tags               = var.tags
  region             = local.region
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_route53_zone" "this" {
  name          = var.zone_name
  comment       = coalesce(var.comment, "${local.base} zone")
  force_destroy = false

  dynamic "vpc" {
    for_each = var.vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = merge(module.naming.tags, { Name = var.zone_name })
}

resource "aws_route53_health_check" "this" {
  for_each = var.health_checks

  type              = each.value.type
  fqdn              = each.value.fqdn
  ip_address        = each.value.ip_address
  port              = coalesce(each.value.port, startswith(each.value.type, "HTTPS") ? 443 : 80)
  resource_path     = each.value.type == "TCP" ? null : each.value.resource_path
  search_string     = each.value.search_string
  failure_threshold = each.value.failure_threshold
  request_interval  = each.value.request_interval
  measure_latency   = each.value.measure_latency
  regions           = each.value.regions
  enable_sni        = startswith(each.value.type, "HTTPS") ? true : null

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}" })
}

resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name == "" ? var.zone_name : "${each.value.name}.${var.zone_name}"
  type            = each.value.type
  ttl             = each.value.alias == null ? each.value.ttl : null
  records         = each.value.alias == null ? each.value.records : null
  set_identifier  = each.value.set_identifier
  health_check_id = try(aws_route53_health_check.this[each.value.health_check].id, null)

  dynamic "alias" {
    for_each = each.value.alias == null ? [] : [each.value.alias]
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = alias.value.evaluate_target_health
    }
  }

  dynamic "failover_routing_policy" {
    for_each = each.value.failover == null ? [] : [each.value.failover]
    content {
      type = failover_routing_policy.value
    }
  }
}
