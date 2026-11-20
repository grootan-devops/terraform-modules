locals {
  ip_protocols = {
    TCP     = ["tcp"]
    TLS     = ["tcp"]
    UDP     = ["udp"]
    TCP_UDP = ["tcp", "udp"]
  }

  listener_traffic = distinct(flatten([
    for l in values(var.listeners) : [for p in local.ip_protocols[l.protocol] : { protocol = p, port = l.port }]
  ]))

  target_traffic = distinct(concat(
    flatten([for t in values(var.target_groups) : [for p in local.ip_protocols[t.protocol] : { protocol = p, port = t.port }]]),
    [for t in values(var.target_groups) : { protocol = "tcp", port = t.health_check.port == "traffic-port" ? t.port : tonumber(t.health_check.port) }]
  ))

  egress_to_vpc = length(var.security_group.egress_cidr_blocks) + length(var.security_group.egress_security_group_ids) == 0

  ingress_rules = merge(
    merge([for i, c in var.security_group.ingress_cidr_blocks : {
      for p in local.listener_traffic : "cidr-${i}-${p.protocol}-${p.port}" => {
        description = "Listener ${p.protocol}/${p.port} from ${c}"
        ip_protocol = p.protocol
        from_port   = p.port
        to_port     = p.port
        cidr_ipv4   = strcontains(c, ":") ? null : c
        cidr_ipv6   = strcontains(c, ":") ? c : null
      }
    }]...),
    merge([for i, sg in var.security_group.ingress_security_group_ids : {
      for p in local.listener_traffic : "sg-${i}-${p.protocol}-${p.port}" => { description = "Listener ${p.protocol}/${p.port} from a security group", ip_protocol = p.protocol, from_port = p.port, to_port = p.port, referenced_security_group_id = sg }
    }]...),
    merge([for i, pl in var.security_group.ingress_prefix_list_ids : {
      for p in local.listener_traffic : "pl-${i}-${p.protocol}-${p.port}" => { description = "Listener ${p.protocol}/${p.port} from a prefix list", ip_protocol = p.protocol, from_port = p.port, to_port = p.port, prefix_list_id = pl }
    }]...)
  )

  egress_rules = merge(
    merge([for i, c in var.security_group.egress_cidr_blocks : {
      for p in local.target_traffic : "cidr-${i}-${p.protocol}-${p.port}" => {
        description = "Targets ${p.protocol}/${p.port} in ${c}"
        ip_protocol = p.protocol
        from_port   = p.port
        to_port     = p.port
        cidr_ipv4   = strcontains(c, ":") ? null : c
        cidr_ipv6   = strcontains(c, ":") ? c : null
      }
    }]...),
    merge([for i, sg in var.security_group.egress_security_group_ids : {
      for p in local.target_traffic : "sg-${i}-${p.protocol}-${p.port}" => { description = "Targets ${p.protocol}/${p.port} in a security group", ip_protocol = p.protocol, from_port = p.port, to_port = p.port, referenced_security_group_id = sg }
    }]...),
    local.egress_to_vpc ? {
      for p in local.target_traffic : "vpc-${p.protocol}-${p.port}" => { description = "Targets ${p.protocol}/${p.port} in the VPC", ip_protocol = p.protocol, from_port = p.port, to_port = p.port, cidr_ipv4 = one(data.aws_vpc.this[*].cidr_block) }
    } : {}
  )

  security_group_ids = concat([module.security_group.id], var.security_group.additional_security_group_ids)

  static_ips = length(var.static_ips.allocation_ids) > 0

  health_check_protocols = {
    for k, t in var.target_groups : k => coalesce(t.health_check.protocol, t.target_type == "alb" ? "HTTP" : "TCP")
  }

  listener_certificates = merge([
    for lk, l in var.listeners : { for i, arn in l.additional_certificate_arns : "${lk}/${i}" => { listener = lk, certificate_arn = arn } }
  ]...)

  targets = merge([
    for tk, t in var.target_groups : { for k, x in t.targets : "${tk}/${k}" => merge(x, { target_group = tk }) }
  ]...)
}
