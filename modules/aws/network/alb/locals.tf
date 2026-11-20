locals {
  listener_ports = concat(var.https_listener.enabled ? [var.https_listener.port] : [], var.http_listener.enabled ? [var.http_listener.port] : [])

  target_ports = distinct(concat(
    [for t in values(var.target_groups) : t.port if t.target_type != "lambda"],
    [for t in values(var.target_groups) : tonumber(t.health_check.port) if t.target_type != "lambda" && t.health_check.port != "traffic-port"]
  ))

  egress_to_vpc = length(var.security_group.egress_cidr_blocks) + length(var.security_group.egress_security_group_ids) == 0

  ingress_rules = merge(
    merge([for i, c in var.security_group.ingress_cidr_blocks : {
      for p in local.listener_ports : "cidr-${i}-${p}" => {
        description = "Listener ${p} from ${c}"
        ip_protocol = "tcp"
        from_port   = p
        to_port     = p
        cidr_ipv4   = strcontains(c, ":") ? null : c
        cidr_ipv6   = strcontains(c, ":") ? c : null
      }
    }]...),
    merge([for i, sg in var.security_group.ingress_security_group_ids : {
      for p in local.listener_ports : "sg-${i}-${p}" => { description = "Listener ${p} from a security group", ip_protocol = "tcp", from_port = p, to_port = p, referenced_security_group_id = sg }
    }]...),
    merge([for i, pl in var.security_group.ingress_prefix_list_ids : {
      for p in local.listener_ports : "pl-${i}-${p}" => { description = "Listener ${p} from a prefix list", ip_protocol = "tcp", from_port = p, to_port = p, prefix_list_id = pl }
    }]...)
  )

  egress_rules = merge(
    merge([for i, c in var.security_group.egress_cidr_blocks : {
      for p in local.target_ports : "cidr-${i}-${p}" => {
        description = "Targets on ${p} in ${c}"
        ip_protocol = "tcp"
        from_port   = p
        to_port     = p
        cidr_ipv4   = strcontains(c, ":") ? null : c
        cidr_ipv6   = strcontains(c, ":") ? c : null
      }
    }]...),
    merge([for i, sg in var.security_group.egress_security_group_ids : {
      for p in local.target_ports : "sg-${i}-${p}" => { description = "Targets on ${p} in a security group", ip_protocol = "tcp", from_port = p, to_port = p, referenced_security_group_id = sg }
    }]...),
    local.egress_to_vpc ? {
      for p in local.target_ports : "vpc-${p}" => { description = "Targets on ${p} in the VPC", ip_protocol = "tcp", from_port = p, to_port = p, cidr_ipv4 = one(data.aws_vpc.this[*].cidr_block) }
    } : {}
  )

  security_group_ids = concat(var.security_group.create ? module.security_group[*].id : [], var.security_group.additional_security_group_ids)

  default_forward = var.default_target_group != null

  rule_listeners = concat(var.https_listener.enabled ? ["https"] : [], var.http_listener.enabled && var.http_listener.forward ? ["http"] : [])

  listener_rules = merge([
    for l in local.rule_listeners : { for k, r in var.listener_rules : "${l}-${k}" => merge(r, { listener = l }) }
  ]...)

  listener_arns = {
    https = one(aws_lb_listener.https[*].arn)
    http  = one(aws_lb_listener.http[*].arn)
  }
}
