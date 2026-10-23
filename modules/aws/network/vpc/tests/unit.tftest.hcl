# The flow log validates its role and destination as ARNs even under the mock
# provider, and endpoint service names are built from the region, so those
# values are pinned instead of left as random strings.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
      name   = "us-west-2"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-network-vpc-flow-logs-role"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/vpc/core-prod-network/flow-logs"
    }
  }
}

variables {
  application                 = "core"
  environment                 = "prod"
  name                        = "network"
  cidr_block                  = "10.0.0.0/16"
  aws_availability_zone_names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs        = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  intra_subnet_cidrs          = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
  kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_vpc.main.tags["Name"] == "core-prod-network" && aws_internet_gateway.this.tags["Name"] == "core-prod-network"
    error_message = "VPC and internet gateway Name tags did not match <application>-<environment>-<name>."
  }

  assert {
    condition = (
      aws_subnet.public["0"].tags["Name"] == "core-prod-network-public-us-west-2a" &&
      aws_subnet.public["1"].tags["Name"] == "core-prod-network-public-us-west-2b" &&
      aws_subnet.public["2"].tags["Name"] == "core-prod-network-public-us-west-2c"
    )
    error_message = "Public subnet Name tags must be <rendered_name>-public-<az>."
  }

  assert {
    condition = (
      aws_subnet.private["0"].tags["Name"] == "core-prod-network-private-us-west-2a" &&
      aws_subnet.private["1"].tags["Name"] == "core-prod-network-private-us-west-2b" &&
      aws_subnet.private["2"].tags["Name"] == "core-prod-network-private-us-west-2c"
    )
    error_message = "Private subnet Name tags must be <rendered_name>-private-<az>."
  }

  assert {
    condition = (
      aws_subnet.intra["0"].tags["Name"] == "core-prod-network-intra-us-west-2a" &&
      aws_subnet.intra["1"].tags["Name"] == "core-prod-network-intra-us-west-2b" &&
      aws_subnet.intra["2"].tags["Name"] == "core-prod-network-intra-us-west-2c"
    )
    error_message = "Intra subnet Name tags must be <rendered_name>-intra-<az>."
  }

  assert {
    condition = (
      aws_route_table.public.tags["Name"] == "core-prod-network-public" &&
      aws_route_table.intra.tags["Name"] == "core-prod-network-intra" &&
      aws_route_table.private["0"].tags["Name"] == "core-prod-network-private-us-west-2a" &&
      aws_route_table.private["1"].tags["Name"] == "core-prod-network-private-us-west-2b" &&
      aws_route_table.private["2"].tags["Name"] == "core-prod-network-private-us-west-2c"
    )
    error_message = "Route table Name tags must be <rendered_name>-<tier>, with one private route table per AZ suffixed by the AZ."
  }

  assert {
    condition = (
      aws_network_acl.public.tags["Name"] == "core-prod-network-public" &&
      aws_network_acl.private.tags["Name"] == "core-prod-network-private" &&
      aws_network_acl.intra.tags["Name"] == "core-prod-network-intra"
    )
    error_message = "Network ACL Name tags must be <rendered_name>-<tier>."
  }

  assert {
    condition = (
      aws_default_security_group.default.tags["Name"] == "core-prod-network-default-deny-all" &&
      aws_default_network_acl.default.tags["Name"] == "core-prod-network-default-deny-all" &&
      aws_default_route_table.default.tags["Name"] == "core-prod-network-default-deny"
    )
    error_message = "Default security group, network ACL and route table Name tags did not match the module convention."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.flow_log[0].name == "/aws/vpc/core-prod-network/flow-logs" &&
      aws_iam_role.flow_log[0].name == "core-prod-network-vpc-flow-logs-role" &&
      aws_iam_role_policy.flow_log[0].name == "core-prod-network-vpc-flow-logs-policy" &&
      aws_flow_log.this[0].tags["Name"] == "core-prod-network-vpc-flow-logs"
    )
    error_message = "Flow log resources did not use the rendered name."
  }

  assert {
    condition     = aws_nat_gateway.regional[0].tags["Name"] == "core-prod-network-regional-nat"
    error_message = "Regional NAT gateway Name tag must be <rendered_name>-regional-nat."
  }

  assert {
    condition = (
      aws_eip.nat["us-west-2a"].tags["Name"] == "core-prod-network-nat-us-west-2a" &&
      aws_eip.nat["us-west-2b"].tags["Name"] == "core-prod-network-nat-us-west-2b" &&
      aws_eip.nat["us-west-2c"].tags["Name"] == "core-prod-network-nat-us-west-2c"
    )
    error_message = "NAT Elastic IP Name tags must be <rendered_name>-nat-<az>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_vpc.main.tags["Name"] == "core-prod"
    error_message = "VPC Name tag did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_subnet.public["0"].tags["Name"] == "core-prod-public-us-west-2a" && aws_subnet.private["1"].tags["Name"] == "core-prod-private-us-west-2b" && aws_subnet.intra["2"].tags["Name"] == "core-prod-intra-us-west-2c"
    error_message = "Subnet Name tags did not use the fallback rendered name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].name == "/aws/vpc/core-prod/flow-logs"
    error_message = "Flow log group name did not use the fallback rendered name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_vpc.main.tags["Name"] == "core-prod" && aws_route_table.private["0"].tags["Name"] == "core-prod-private-us-west-2a"
    error_message = "Names did not fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "1234"
      Team       = "platform"
    }
  }

  assert {
    condition     = aws_vpc.main.tags["Application"] == "core" && aws_vpc.main.tags["Environment"] == "prod" && aws_vpc.main.tags["Name"] == "core-prod-network"
    error_message = "VPC is missing the Application, Environment or Name governance tags."
  }

  assert {
    condition     = aws_vpc.main.tags["CostCenter"] == "1234" && aws_vpc.main.tags["Team"] == "platform"
    error_message = "Caller tags from var.tags were not preserved on the VPC."
  }

  assert {
    condition = alltrue(flatten([
      for tier in [aws_subnet.public, aws_subnet.private, aws_subnet.intra] : [
        for s in tier : s.tags["Application"] == "core" && s.tags["Environment"] == "prod" && s.tags["CostCenter"] == "1234"
      ]
    ]))
    error_message = "Every subnet must carry the governance tags and the caller tags."
  }

  assert {
    condition = (
      alltrue([for s in aws_subnet.public : s.tags["Tier"] == "public"]) &&
      alltrue([for s in aws_subnet.private : s.tags["Tier"] == "private"]) &&
      alltrue([for s in aws_subnet.intra : s.tags["Tier"] == "intra"])
    )
    error_message = "Subnets must carry a Tier tag matching their tier."
  }

  assert {
    condition = (
      aws_route_table.public.tags["Tier"] == "public" &&
      aws_route_table.intra.tags["Tier"] == "intra" &&
      alltrue([for rt in aws_route_table.private : rt.tags["Tier"] == "private" && rt.tags["CostCenter"] == "1234"])
    )
    error_message = "Route tables must carry the Tier tag and the caller tags."
  }

  assert {
    condition = (
      aws_network_acl.public.tags["Tier"] == "public" &&
      aws_network_acl.private.tags["Tier"] == "private" &&
      aws_network_acl.intra.tags["Tier"] == "intra" &&
      aws_network_acl.intra.tags["Team"] == "platform"
    )
    error_message = "Network ACLs must carry the Tier tag and the caller tags."
  }

  assert {
    condition     = aws_internet_gateway.this.tags["Application"] == "core" && aws_internet_gateway.this.tags["CostCenter"] == "1234"
    error_message = "Internet gateway did not receive the module tags."
  }

  assert {
    condition = (
      aws_default_security_group.default.tags["Environment"] == "prod" &&
      aws_default_network_acl.default.tags["Environment"] == "prod" &&
      aws_default_route_table.default.tags["Environment"] == "prod" &&
      aws_default_security_group.default.tags["CostCenter"] == "1234"
    )
    error_message = "Default security group, network ACL and route table did not receive the module tags."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.flow_log[0].tags["Name"] == "core-prod-network-vpc-flow-logs" &&
      aws_cloudwatch_log_group.flow_log[0].tags["Application"] == "core" &&
      aws_iam_role.flow_log[0].tags["Name"] == "core-prod-network-vpc-flow-logs-role" &&
      aws_iam_role.flow_log[0].tags["CostCenter"] == "1234" &&
      aws_flow_log.this[0].tags["Environment"] == "prod"
    )
    error_message = "Flow log resources must carry governance and caller tags with Name overridden per resource."
  }

  assert {
    condition     = aws_nat_gateway.regional[0].tags["Application"] == "core" && aws_nat_gateway.regional[0].tags["Team"] == "platform" && aws_eip.nat["us-west-2a"].tags["CostCenter"] == "1234"
    error_message = "NAT gateway and Elastic IPs did not receive the module tags."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "VPC flow logs must be on by default and capture ALL traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Flow log group must be encrypted with var.kms_key_arn by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].retention_in_days == 90 && aws_cloudwatch_log_group.flow_log[0].log_group_class == "STANDARD"
    error_message = "Flow log group must default to 90-day retention in the STANDARD class."
  }

  assert {
    condition     = jsondecode(aws_iam_role.flow_log[0].assume_role_policy).Statement[0].Principal.Service == "vpc-flow-logs.amazonaws.com"
    error_message = "Flow log role must only be assumable by vpc-flow-logs.amazonaws.com."
  }

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "Default security group must have no ingress or egress rules."
  }

  assert {
    condition     = length(aws_default_network_acl.default.ingress) == 0 && length(aws_default_network_acl.default.egress) == 0
    error_message = "Default network ACL must have no rules, denying all traffic."
  }

  assert {
    condition     = length(aws_default_route_table.default.route) == 0
    error_message = "Default route table must have no routes."
  }

  assert {
    condition = alltrue(flatten([
      for tier in [aws_subnet.public, aws_subnet.private, aws_subnet.intra] : [for s in tier : s.map_public_ip_on_launch == false]
    ]))
    error_message = "No subnet, including public ones, may auto-assign public IPs."
  }

  assert {
    condition     = length(aws_route.intra_internet_gateway) == 0 && length(aws_route.private_internet_gateway) == 0
    error_message = "Intra and private subnets must not route to the internet gateway by default."
  }

  assert {
    condition     = length(aws_network_acl_rule.intra) == 2 && alltrue([for r in aws_network_acl_rule.intra : r.cidr_block == "10.0.0.0/16" && r.rule_action == "allow"])
    error_message = "Intra network ACL must only allow traffic to and from the VPC CIDR."
  }

  assert {
    condition     = length(aws_security_group.vpc_endpoints) == 0 && length(aws_vpc_endpoint.interface) == 0 && length(aws_vpc_endpoint.s3_gateway) == 0 && length(aws_vpc_endpoint.dynamodb_gateway) == 0
    error_message = "VPC endpoints must be off by default."
  }
}

run "verify_flow_log_wiring" {
  command = apply

  assert {
    condition     = aws_flow_log.this[0].vpc_id == aws_vpc.main.id
    error_message = "Flow log must be attached to the module's VPC."
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination == aws_cloudwatch_log_group.flow_log[0].arn && aws_flow_log.this[0].iam_role_arn == aws_iam_role.flow_log[0].arn
    error_message = "Flow log must deliver to the module's log group using the module's role."
  }

  assert {
    condition     = aws_iam_role_policy.flow_log[0].role == aws_iam_role.flow_log[0].id
    error_message = "Flow log policy must be attached to the flow log role."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.flow_log[0].policy).Statement[0].Resource == "${aws_cloudwatch_log_group.flow_log[0].arn}:*"
    error_message = "Flow log policy must be scoped to the module's log group."
  }

  assert {
    condition     = output.vpc_id == aws_vpc.main.id && output.cidr_block == "10.0.0.0/16"
    error_message = "vpc_id and cidr_block outputs did not match the VPC."
  }

  assert {
    condition = (
      output.public_subnets == [for k in ["0", "1", "2"] : aws_subnet.public[k].id] &&
      output.private_subnets == [for k in ["0", "1", "2"] : aws_subnet.private[k].id] &&
      output.intra_subnets == [for k in ["0", "1", "2"] : aws_subnet.intra[k].id]
    )
    error_message = "Subnet outputs must list the subnet ids of each tier in CIDR order."
  }
}

run "verify_subnet_layout" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.intra) == 3
    error_message = "One subnet must be created per CIDR in each tier."
  }

  assert {
    condition = alltrue([
      for i, az in ["us-west-2a", "us-west-2b", "us-west-2c"] :
      aws_subnet.public[tostring(i)].availability_zone == az &&
      aws_subnet.private[tostring(i)].availability_zone == az &&
      aws_subnet.intra[tostring(i)].availability_zone == az
    ])
    error_message = "Subnets must be spread across the AZs in list order."
  }

  assert {
    condition = (
      [for k in ["0", "1", "2"] : aws_subnet.public[k].cidr_block] == ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"] &&
      [for k in ["0", "1", "2"] : aws_subnet.private[k].cidr_block] == ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"] &&
      [for k in ["0", "1", "2"] : aws_subnet.intra[k].cidr_block] == ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
    )
    error_message = "Subnet CIDR blocks did not match the per-tier CIDR lists."
  }

  assert {
    condition     = length(aws_route_table.private) == 3 && length(aws_route_table_association.private) == 3 && length(aws_route_table_association.public) == 3 && length(aws_route_table_association.intra) == 3
    error_message = "Each private subnet needs its own route table, and every subnet a route table association."
  }

  assert {
    condition     = length(aws_network_acl_association.public) == 3 && length(aws_network_acl_association.private) == 3 && length(aws_network_acl_association.intra) == 3
    error_message = "Every subnet must be associated with its tier's network ACL."
  }

  assert {
    condition     = aws_route.public_internet_gateway.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route table must have a default route to the internet gateway."
  }

  assert {
    condition     = length(aws_route.private_nat_gateway) == 3 && alltrue([for r in aws_route.private_nat_gateway : r.destination_cidr_block == "0.0.0.0/0"])
    error_message = "Each private route table must have a default route through the NAT gateway."
  }
}

run "verify_subnet_counts_follow_cidr_lists" {
  command = plan

  variables {
    aws_availability_zone_names = ["us-west-2a", "us-west-2b"]
    public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnet_cidrs        = ["10.0.10.0/24"]
    intra_subnet_cidrs          = []
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 1 && length(aws_subnet.intra) == 0
    error_message = "Subnet counts must follow the length of each CIDR list."
  }

  assert {
    condition     = length(aws_route_table.private) == 1 && length(aws_route.private_nat_gateway) == 1 && length(aws_route_table_association.intra) == 0
    error_message = "Private route tables and routes must follow the private subnet count."
  }

  assert {
    condition     = length(aws_eip.nat) == 2 && length(aws_nat_gateway.regional[0].availability_zone_address) == 2
    error_message = "The regional NAT gateway must get one address per AZ."
  }
}

run "verify_regional_nat_default" {
  command = apply

  assert {
    condition     = length(aws_nat_gateway.regional) == 1 && length(aws_nat_gateway.single) == 0 && length(aws_nat_gateway.per_az) == 0
    error_message = "NAT must default to a single regional NAT gateway."
  }

  assert {
    condition     = aws_nat_gateway.regional[0].availability_mode == "regional" && aws_nat_gateway.regional[0].connectivity_type == "public" && aws_nat_gateway.regional[0].vpc_id == aws_vpc.main.id
    error_message = "Regional NAT gateway must be public, in regional availability mode, in the module's VPC."
  }

  assert {
    condition     = toset([for a in aws_nat_gateway.regional[0].availability_zone_address : a.availability_zone]) == toset(["us-west-2a", "us-west-2b", "us-west-2c"])
    error_message = "Regional NAT gateway must have an address in every AZ."
  }

  assert {
    condition = alltrue([
      for a in aws_nat_gateway.regional[0].availability_zone_address : a.allocation_ids == toset([aws_eip.nat[a.availability_zone].id])
    ])
    error_message = "Each regional NAT AZ address must use the Elastic IP created for that AZ."
  }

  assert {
    condition     = length(aws_eip.nat) == 3 && alltrue([for e in aws_eip.nat : e.domain == "vpc" && e.public_ipv4_pool == "amazon"])
    error_message = "One VPC Elastic IP from the Amazon pool must be created per AZ."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_nat_gateway : r.nat_gateway_id == aws_nat_gateway.regional[0].id])
    error_message = "Private default routes must point at the regional NAT gateway."
  }
}

run "verify_single_az_nat" {
  command = apply

  variables {
    nat = {
      mode = "single_az"
    }
  }

  assert {
    condition     = length(aws_nat_gateway.single) == 1 && length(aws_nat_gateway.regional) == 0 && length(aws_nat_gateway.per_az) == 0
    error_message = "single_az mode must create exactly one zonal NAT gateway."
  }

  assert {
    condition     = aws_nat_gateway.single[0].availability_mode == "zonal" && aws_nat_gateway.single[0].subnet_id == aws_subnet.public["0"].id
    error_message = "Single NAT gateway must be zonal and sit in the first public subnet."
  }

  assert {
    condition     = keys(aws_eip.nat) == ["us-west-2a"] && aws_nat_gateway.single[0].allocation_id == aws_eip.nat["us-west-2a"].id
    error_message = "Single NAT gateway must use one Elastic IP in the first AZ."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_nat_gateway : r.nat_gateway_id == aws_nat_gateway.single[0].id]) && length(aws_route.private_nat_gateway) == 3
    error_message = "All private default routes must point at the single NAT gateway."
  }
}

run "verify_per_az_nat" {
  command = apply

  variables {
    nat = {
      mode = "per_az"
    }
  }

  assert {
    condition     = length(aws_nat_gateway.per_az) == 3 && length(aws_nat_gateway.regional) == 0 && length(aws_nat_gateway.single) == 0
    error_message = "per_az mode must create one zonal NAT gateway per AZ."
  }

  assert {
    condition = alltrue([
      for i, az in ["us-west-2a", "us-west-2b", "us-west-2c"] :
      aws_nat_gateway.per_az[az].subnet_id == aws_subnet.public[tostring(i)].id &&
      aws_nat_gateway.per_az[az].allocation_id == aws_eip.nat[az].id &&
      aws_nat_gateway.per_az[az].tags["Name"] == "core-prod-network-nat-${az}"
    ])
    error_message = "Each per-AZ NAT gateway must sit in that AZ's public subnet with that AZ's Elastic IP and a -nat-<az> Name."
  }

  assert {
    condition = alltrue([
      for i, az in ["us-west-2a", "us-west-2b", "us-west-2c"] :
      aws_route.private_nat_gateway[tostring(i)].nat_gateway_id == aws_nat_gateway.per_az[az].id
    ])
    error_message = "Each private route table must route through the NAT gateway in its own AZ."
  }
}

run "verify_nat_disabled" {
  command = plan

  variables {
    nat = {
      enabled = false
    }
  }

  assert {
    condition     = length(aws_nat_gateway.regional) == 0 && length(aws_nat_gateway.single) == 0 && length(aws_nat_gateway.per_az) == 0 && length(aws_eip.nat) == 0
    error_message = "No NAT gateways or Elastic IPs must be created when nat.enabled is false."
  }

  assert {
    condition     = length(aws_route.private_nat_gateway) == 0
    error_message = "No private NAT routes must be created when nat.enabled is false."
  }
}

run "verify_existing_eip_allocation_ids" {
  command = plan

  variables {
    nat = {
      eip_allocation_ids = {
        "us-west-2a" = "eipalloc-0123456789abcdef0"
      }
    }
  }

  assert {
    condition     = toset(keys(aws_eip.nat)) == toset(["us-west-2b", "us-west-2c"])
    error_message = "Elastic IPs must only be created for AZs without a supplied allocation id."
  }

  assert {
    condition = anytrue([
      for a in aws_nat_gateway.regional[0].availability_zone_address :
      a.availability_zone == "us-west-2a" && a.allocation_ids == toset(["eipalloc-0123456789abcdef0"])
    ])
    error_message = "The regional NAT gateway must use the supplied allocation id for its AZ."
  }
}

run "verify_internet_gateway_route_toggles" {
  command = plan

  variables {
    private_subnet_internet_gateway = true
    intra_subnet_internet_gateway   = true
  }

  assert {
    condition     = length(aws_route.private_internet_gateway) == 3 && length(aws_route.private_nat_gateway) == 0
    error_message = "private_subnet_internet_gateway must replace the private NAT routes with internet gateway routes."
  }

  assert {
    condition     = length(aws_route.intra_internet_gateway) == 1 && aws_route.intra_internet_gateway[0].destination_cidr_block == "0.0.0.0/0"
    error_message = "intra_subnet_internet_gateway must add a default route to the intra route table."
  }
}

run "verify_flow_logs_disabled" {
  command = plan

  variables {
    cloudwatch_logs = {
      enabled = false
    }
  }

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(aws_cloudwatch_log_group.flow_log) == 0 && length(aws_iam_role.flow_log) == 0 && length(aws_iam_role_policy.flow_log) == 0
    error_message = "No flow log resources must be created when cloudwatch_logs.enabled is false."
  }
}

run "verify_flow_logs_without_vpc_flow_export" {
  command = plan

  variables {
    cloudwatch_logs = {
      exports = []
    }
  }

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(aws_cloudwatch_log_group.flow_log) == 0
    error_message = "No flow log must be created when vpc_flow is not in cloudwatch_logs.exports."
  }
}

run "verify_flow_logs_overrides" {
  command = plan

  variables {
    cloudwatch_logs = {
      retention_in_days = { vpc_flow = 365 }
      kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].retention_in_days == 365
    error_message = "cloudwatch_logs.retention_in_days.vpc_flow did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over var.kms_key_arn."
  }
}

run "verify_vpc_endpoints_enabled" {
  command = apply

  variables {
    vpc_endpoints = {
      enabled          = true
      services         = ["ecr.api", "logs"]
      s3_buckets       = ["core-prod-assets"]
      dynamodb_gateway = true
      policies = {
        logs = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"logs:*\",\"Resource\":\"*\"}]}"
      }
    }
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 2 && aws_vpc_endpoint.interface["ecr.api"].service_name == "com.amazonaws.us-west-2.ecr.api" && aws_vpc_endpoint.interface["logs"].service_name == "com.amazonaws.us-west-2.logs"
    error_message = "One interface endpoint must be created per service, named for the current region."
  }

  assert {
    condition = alltrue([
      for e in aws_vpc_endpoint.interface :
      e.vpc_endpoint_type == "Interface" && e.private_dns_enabled == true && e.vpc_id == aws_vpc.main.id &&
      e.subnet_ids == toset([for s in aws_subnet.private : s.id]) &&
      e.security_group_ids == toset([aws_security_group.vpc_endpoints[0].id])
    ])
    error_message = "Interface endpoints must default to private DNS in the private subnets behind the endpoint security group."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["logs"].policy == "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"logs:*\",\"Resource\":\"*\"}]}"
    error_message = "Per-service endpoint policy did not flow through."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["logs"].tags["Name"] == "core-prod-network-logs-endpoint" && aws_vpc_endpoint.interface["logs"].tags["Application"] == "core"
    error_message = "Interface endpoint tags must carry governance tags with Name <rendered_name>-<service>-endpoint."
  }

  assert {
    condition     = aws_security_group.vpc_endpoints[0].name == "core-prod-network-vpc-endpoints" && aws_security_group.vpc_endpoints[0].tags["Name"] == "core-prod-network-vpc-endpoints-sg"
    error_message = "Endpoint security group name or Name tag did not match the module convention."
  }

  assert {
    condition = length(aws_security_group.vpc_endpoints[0].ingress) == 1 && alltrue([
      for r in aws_security_group.vpc_endpoints[0].ingress :
      r.from_port == 443 && r.to_port == 443 && r.protocol == "tcp" && r.cidr_blocks == tolist(["10.0.0.0/16"])
    ])
    error_message = "Endpoint security group must only allow HTTPS from the VPC CIDR."
  }

  assert {
    condition     = aws_vpc_endpoint.s3_gateway[0].service_name == "com.amazonaws.us-west-2.s3" && aws_vpc_endpoint.s3_gateway[0].vpc_endpoint_type == "Gateway"
    error_message = "S3 gateway endpoint must be created when s3_buckets is set."
  }

  assert {
    condition     = aws_vpc_endpoint.s3_gateway[0].route_table_ids == toset(concat([aws_route_table.public.id, aws_route_table.intra.id], [for rt in aws_route_table.private : rt.id]))
    error_message = "Gateway endpoints must default to the public, private and intra route tables."
  }

  assert {
    condition     = toset(jsondecode(aws_vpc_endpoint.s3_gateway[0].policy).Statement[0].Resource) == toset(["arn:aws:s3:::core-prod-assets", "arn:aws:s3:::core-prod-assets/*"])
    error_message = "S3 gateway endpoint policy must be scoped to the listed buckets."
  }

  assert {
    condition     = aws_vpc_endpoint.s3_gateway[0].tags["Name"] == "core-prod-network-s3-gateway-endpoint" && aws_vpc_endpoint.dynamodb_gateway[0].tags["Name"] == "core-prod-network-dynamodb-gateway-endpoint"
    error_message = "Gateway endpoint Name tags did not match the module convention."
  }

  assert {
    condition     = aws_vpc_endpoint.dynamodb_gateway[0].service_name == "com.amazonaws.us-west-2.dynamodb" && aws_vpc_endpoint.dynamodb_gateway[0].route_table_ids == aws_vpc_endpoint.s3_gateway[0].route_table_ids
    error_message = "DynamoDB gateway endpoint must be created on the same route tables when dynamodb_gateway is true."
  }
}

run "verify_vpc_endpoint_placement_overrides" {
  command = apply

  variables {
    vpc_endpoints = {
      enabled                   = true
      services                  = ["ssm"]
      s3_buckets                = ["core-prod-assets"]
      gateway_route_table_tiers = ["private"]
      interface_subnet_tier     = "intra"
      subnet_indices            = [0, 2]
      private_dns_enabled       = false
    }
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].subnet_ids == toset([aws_subnet.intra["0"].id, aws_subnet.intra["2"].id])
    error_message = "interface_subnet_tier and subnet_indices must pick the interface endpoint subnets."
  }

  assert {
    condition     = aws_vpc_endpoint.interface["ssm"].private_dns_enabled == false
    error_message = "private_dns_enabled override did not flow through."
  }

  assert {
    condition     = aws_vpc_endpoint.s3_gateway[0].route_table_ids == toset([for rt in aws_route_table.private : rt.id])
    error_message = "gateway_route_table_tiers must limit gateway endpoints to the chosen tiers."
  }

  assert {
    condition     = length(aws_vpc_endpoint.dynamodb_gateway) == 0
    error_message = "DynamoDB gateway endpoint must stay off unless dynamodb_gateway is true."
  }
}

run "verify_dns_and_dhcp_defaults" {
  command = plan

  assert {
    condition     = aws_vpc.main.enable_dns_support == true && aws_vpc.main.enable_dns_hostnames == true
    error_message = "VPC DNS support and hostnames must be enabled by default."
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16" && aws_vpc.main.instance_tenancy == "default" && aws_vpc.main.enable_network_address_usage_metrics == false
    error_message = "VPC CIDR, tenancy or address usage metrics did not match the shipped defaults."
  }

  assert {
    condition     = length(aws_vpc_dhcp_options.this) == 0 && length(aws_vpc_dhcp_options_association.this) == 0
    error_message = "DHCP options must be off by default."
  }

  assert {
    condition     = length(aws_route.public_additional) == 0 && length(aws_route.private_additional) == 0 && length(aws_route.intra_additional) == 0
    error_message = "No additional routes must be created by default."
  }
}

run "verify_dns_and_dhcp_overrides" {
  command = apply

  variables {
    dns = {
      enable_dns_support   = false
      enable_dns_hostnames = false
    }

    dhcp_options = {
      enabled             = true
      domain_name         = "corp.example.com"
      domain_name_servers = ["10.0.0.2"]
      ntp_servers         = ["169.254.169.123"]
    }
  }

  assert {
    condition     = aws_vpc.main.enable_dns_support == false && aws_vpc.main.enable_dns_hostnames == false
    error_message = "dns overrides did not flow through to the VPC."
  }

  assert {
    condition     = aws_vpc_dhcp_options.this[0].domain_name == "corp.example.com" && aws_vpc_dhcp_options.this[0].domain_name_servers == tolist(["10.0.0.2"]) && aws_vpc_dhcp_options.this[0].ntp_servers == tolist(["169.254.169.123"])
    error_message = "DHCP option values did not flow through."
  }

  assert {
    condition     = aws_vpc_dhcp_options.this[0].tags["Name"] == "core-prod-network-dhcp" && aws_vpc_dhcp_options.this[0].tags["Application"] == "core"
    error_message = "DHCP options tags must carry governance tags with Name <rendered_name>-dhcp."
  }

  assert {
    condition     = aws_vpc_dhcp_options_association.this[0].vpc_id == aws_vpc.main.id && aws_vpc_dhcp_options_association.this[0].dhcp_options_id == aws_vpc_dhcp_options.this[0].id
    error_message = "DHCP options must be associated with the module's VPC."
  }
}

run "verify_nacl_default_rules" {
  command = plan

  assert {
    condition     = toset(keys(aws_network_acl_rule.public)) == toset(["ingress-100", "ingress-110", "ingress-112", "ingress-113", "ingress-116", "ingress-117", "ingress-200", "egress-100"])
    error_message = "Public network ACL did not get the shipped default rule set."
  }

  assert {
    condition     = aws_network_acl_rule.public["ingress-100"].cidr_block == "10.0.0.0/16" && aws_network_acl_rule.public["ingress-100"].protocol == "-1"
    error_message = "Public network ACL rule 100 must allow all traffic from the VPC CIDR."
  }

  assert {
    condition     = aws_network_acl_rule.public["egress-100"].egress == true && aws_network_acl_rule.public["egress-100"].rule_action == "allow"
    error_message = "Public network ACL must allow all egress."
  }
}

run "verify_nacl_custom_rules" {
  command = plan

  variables {
    nacl = {
      public = [
        { rule_no = 110, egress = false, protocol = "tcp", action = "deny", cidr_block = "0.0.0.0/0", from_port = 22, to_port = 22 },
        { rule_no = 120, egress = false, protocol = "tcp", action = "allow", cidr_block = "192.168.0.0/16", from_port = 8443, to_port = 8443 },
      ]
      intra = [
        { rule_no = 150, egress = true, protocol = "tcp", action = "allow", cidr_block = "192.168.0.0/16", from_port = 5432, to_port = 5432 },
      ]
    }
  }

  assert {
    condition     = aws_network_acl_rule.public["ingress-110"].rule_action == "deny"
    error_message = "A custom rule with the same direction and rule number must replace the default rule."
  }

  assert {
    condition     = aws_network_acl_rule.public["ingress-120"].from_port == 8443 && aws_network_acl_rule.public["ingress-120"].cidr_block == "192.168.0.0/16" && length(aws_network_acl_rule.public) == 9
    error_message = "A custom rule with a new rule number must be added alongside the defaults."
  }

  assert {
    condition     = !contains(keys(aws_network_acl_rule.private), "ingress-120") && alltrue([for r in aws_network_acl_rule.private : r.rule_action == "allow"])
    error_message = "Custom public rules must not leak into the private network ACL."
  }

  assert {
    condition     = aws_network_acl_rule.intra["egress-150"].egress == true && aws_network_acl_rule.intra["egress-150"].to_port == 5432 && length(aws_network_acl_rule.intra) == 3
    error_message = "Custom intra rules must be added to the intra network ACL."
  }
}

run "verify_additional_routes" {
  command = plan

  variables {
    additional_routes = {
      public = [
        { destination_cidr_block = "192.168.0.0/16", transit_gateway_id = "tgw-0123456789abcdef0" },
      ]
      private = [
        { destination_cidr_block = "192.168.0.0/16", transit_gateway_id = "tgw-0123456789abcdef0" },
      ]
      intra = [
        { destination_cidr_block = "172.16.0.0/12", vpc_peering_connection_id = "pcx-0123456789abcdef0" },
      ]
    }
  }

  assert {
    condition     = aws_route.public_additional["192.168.0.0/16"].transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "Public additional route did not flow through."
  }

  assert {
    condition     = toset(keys(aws_route.private_additional)) == toset(["0-192.168.0.0/16", "1-192.168.0.0/16", "2-192.168.0.0/16"])
    error_message = "A private additional route must be created in every private route table."
  }

  assert {
    condition     = alltrue([for r in aws_route.private_additional : r.transit_gateway_id == "tgw-0123456789abcdef0" && r.destination_cidr_block == "192.168.0.0/16"])
    error_message = "Private additional route targets did not flow through."
  }

  assert {
    condition     = aws_route.intra_additional["172.16.0.0/12"].vpc_peering_connection_id == "pcx-0123456789abcdef0"
    error_message = "Intra additional route did not flow through."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_cidr_block_fails" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/33"
  }

  expect_failures = [var.cidr_block]
}

run "verify_invalid_nat_mode_fails" {
  command = plan

  variables {
    nat = {
      mode = "multi_az"
    }
  }

  expect_failures = [var.nat]
}
