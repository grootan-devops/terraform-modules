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

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-flow-logs-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vpc/core-prod/flow-logs"
    }
  }

  mock_resource "aws_vpc" {
    defaults = {
      arn = "arn:aws:ec2:eu-west-1:123456789012:vpc/vpc-0a1b2c3d4e5f67890"
    }
  }

  mock_resource "aws_eip" {
    defaults = {
      public_ip = "203.0.113.10"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  cidr_block  = "10.0.0.0/16"
  tags        = { Team = "network" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16" && aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "The VPC must use cidr_block with DNS support and hostnames."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0 && length(aws_default_route_table.this.route) == 0
    error_message = "The default security group and route table must be empty (EC2.2)."
  }

  assert {
    condition     = output.azs == tolist(["eu-west-1a", "eu-west-1b", "eu-west-1c"]) && length(aws_subnet.this) == 9
    error_message = "Three AZs and three tiers by default."
  }

  assert {
    condition     = output.private_subnet_cidrs == ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"] && output.intra_subnet_cidrs == ["10.0.224.0/24", "10.0.225.0/24", "10.0.226.0/24"] && output.public_subnet_cidrs == ["10.0.240.0/24", "10.0.241.0/24", "10.0.242.0/24"]
    error_message = "Computed CIDRs: private /20 blocks 0-2, intra /24s in block 14, public /24s in block 15."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.this : !s.map_public_ip_on_launch])
    error_message = "No subnet assigns public IPs (EC2.15)."
  }

  assert {
    condition     = aws_subnet.this["private-1"].availability_zone == "eu-west-1b" && aws_subnet.this["private-1"].tags["Name"] == "core-prod-private-eu-west-1b" && aws_subnet.this["private-1"].tags["Tier"] == "private"
    error_message = "Subnets are placed and named by tier and AZ."
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 1 && length(aws_route.internet) == 1 && aws_route.internet[0].destination_cidr_block == "0.0.0.0/0"
    error_message = "Public subnets get an internet gateway and a default route."
  }

  assert {
    condition     = keys(aws_route_table.this) == ["intra", "private-0", "private-1", "private-2", "public"]
    error_message = "One public, one intra and one private route table per AZ."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1 && keys(aws_route.nat) == ["private-0", "private-1", "private-2"]
    error_message = "Default NAT: one gateway that every private route table uses."
  }

  assert {
    condition     = keys(aws_network_acl.this) == ["intra", "private", "public"] && length(aws_network_acl_association.this) == 9
    error_message = "One network ACL per tier, associated with every subnet of the tier."
  }

  assert {
    condition     = !anytrue([for r in aws_network_acl_rule.this : !r.egress && r.cidr_block == "0.0.0.0/0" && (r.protocol == "-1" || (r.from_port <= 22 && r.to_port >= 22) || (r.from_port <= 3389 && r.to_port >= 3389))])
    error_message = "No default network ACL rule opens 22 or 3389 to the internet (EC2.21)."
  }

  assert {
    condition     = aws_network_acl_rule.this["intra-egress-100"].cidr_block == "10.0.0.0/16" && aws_network_acl_rule.this["intra-ingress-100"].cidr_block == "10.0.0.0/16" && length([for k, r in aws_network_acl_rule.this : k if startswith(k, "intra-")]) == 2
    error_message = "The intra network ACL allows only VPC traffic."
  }

  assert {
    condition     = aws_flow_log.this[0].traffic_type == "ALL" && aws_flow_log.this[0].log_destination_type == "cloud-watch-logs" && aws_flow_log.this[0].max_aggregation_interval == 600
    error_message = "Flow logs capture ALL traffic to CloudWatch Logs by default (EC2.6)."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/vpc/core-prod/flow-logs" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null && output.kms_key_arn == null
    error_message = "The flow log group keeps 365 days with service encryption by default."
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "core-prod" && aws_vpc.this.tags["Team"] == "network" && aws_vpc.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = length(aws_vpc_endpoint.this) == 0 && length(module.endpoint_security_group) == 0 && output.vpc_endpoint_security_group_id == null && length(aws_vpc_dhcp_options.this) == 0
    error_message = "No endpoints and no DHCP options by default."
  }
}

run "flow_log_role" {
  command = plan

  variables {
    name = "main"
  }

  assert {
    condition     = module.role[0].name == "core-prod-main-flow-logs-eu-west-1" && aws_vpc.this.tags["Name"] == "core-prod-main"
    error_message = "Names are <application>-<environment>-<name>; the role adds its purpose and Region."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["vpc-flow-logs.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:ec2:eu-west-1:123456789012:vpc-flow-log/*"]
    error_message = "Only VPC flow logs of this account and Region may assume the role."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["WriteFlowLogs", "DescribeLogGroups"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vpc/core-prod-main/flow-logs:*"]
    error_message = "The role may only write to its own log group."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && length(module.log_group) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_flow_logs" {
  command   = apply
  state_key = "kms"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group[0].kms_key_arn
    error_message = "The module key must encrypt the flow log group."
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination == module.log_group[0].arn && aws_flow_log.this[0].iam_role_arn == module.role[0].arn
    error_message = "The flow log must write to the module log group with the module role."
  }
}

run "caller_key_id_and_log_overrides" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { retention_in_days = 731, deletion_protection_enabled = false }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "A key ID must be used as the key ARN; retention must follow cloudwatch_logs."
  }
}

run "nat_per_az" {
  command   = apply
  state_key = "per_az"

  variables {
    nat = { mode = "per_az" }
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(output.nat_gateway_ids) == 3 && output.nat_public_ips == ["203.0.113.10", "203.0.113.10", "203.0.113.10"]
    error_message = "per_az creates one NAT gateway and Elastic IP per AZ."
  }

  assert {
    condition     = aws_route.nat["private-1"].nat_gateway_id == aws_nat_gateway.this["1"].id && aws_nat_gateway.this["1"].subnet_id == aws_subnet.this["public-1"].id
    error_message = "Each private route table uses the NAT gateway in its own AZ."
  }

  assert {
    condition     = output.private_subnet_ids == [aws_subnet.this["private-0"].id, aws_subnet.this["private-1"].id, aws_subnet.this["private-2"].id] && length(output.private_route_table_ids) == 3 && length(output.public_route_table_ids) == 1
    error_message = "Subnet and route table outputs follow AZ order."
  }
}

run "nat_none" {
  command = plan

  variables {
    nat = { mode = "none" }
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.nat) == 0 && output.nat_gateway_ids == []
    error_message = "mode none plans without NAT gateways or NAT routes."
  }

  assert {
    condition     = length(aws_route.internet) == 1
    error_message = "Public subnets keep their internet route."
  }
}

run "private_only_vpc" {
  command = plan

  variables {
    az_count       = 2
    public_subnets = { enabled = false }
    intra_subnets  = { enabled = false }
    nat            = { mode = "none" }
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_route.internet) == 0 && keys(aws_route_table.this) == ["private-0", "private-1"]
    error_message = "No internet gateway or public route table without public subnets."
  }

  assert {
    condition     = keys(aws_network_acl.this) == ["private"] && length(aws_subnet.this) == 2 && length([for k in keys(aws_network_acl_rule.this) : k if !startswith(k, "private-")]) == 0
    error_message = "Network ACLs and rules exist only for tiers with subnets."
  }
}

run "explicit_azs_and_cidrs" {
  command = plan

  variables {
    cidr_block      = "10.10.0.0/24"
    azs             = ["eu-west-1b", "eu-west-1c"]
    public_subnets  = { cidrs = ["10.10.0.0/28", "10.10.0.16/28"] }
    private_subnets = { cidrs = ["10.10.0.64/26", "10.10.0.128/26"] }
    intra_subnets   = { cidrs = ["10.10.0.32/28", "10.10.0.48/28"] }
  }

  assert {
    condition     = output.azs == tolist(["eu-west-1b", "eu-west-1c"]) && output.private_subnet_cidrs == ["10.10.0.64/26", "10.10.0.128/26"] && aws_subnet.this["public-1"].availability_zone == "eu-west-1c"
    error_message = "Explicit AZs and CIDRs replace the computed layout."
  }
}

run "nacl_rules_and_routes" {
  command = plan

  variables {
    nacl_rules = {
      no_http = { tier = "public", rule_number = 110, action = "deny", cidr_block = "0.0.0.0/0", from_port = 80, to_port = 80 }
      bastion = { tier = "private", rule_number = 120, cidr_block = "203.0.113.0/24", from_port = 22, to_port = 22 }
      ignored = { tier = "intra", rule_number = 120, cidr_block = "10.1.0.0/16", from_port = 443, to_port = 443 }
    }
    intra_subnets = { enabled = false }
    routes = {
      tgw = { destination_cidr_block = "10.100.0.0/16", transit_gateway_id = "tgw-0123456789abcdef0" }
    }
  }

  assert {
    condition     = aws_network_acl_rule.this["public-ingress-110"].rule_action == "deny" && aws_network_acl_rule.this["private-ingress-120"].from_port == 22 && !contains(keys(aws_network_acl_rule.this), "intra-ingress-120")
    error_message = "A caller rule replaces the default with the same number and rules for disabled tiers are skipped."
  }

  assert {
    condition     = keys(aws_route.this) == ["tgw-private-0", "tgw-private-1", "tgw-private-2"] && aws_route.this["tgw-private-0"].transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "Routes are added to every route table of the listed tiers that exist."
  }
}

run "flow_logs_to_s3" {
  command = plan

  variables {
    flow_logs = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/vpc", traffic_type = "REJECT" }
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination_type == "s3" && aws_flow_log.this[0].log_destination == "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/vpc" && aws_flow_log.this[0].iam_role_arn == null
    error_message = "S3 flow logs go to the bucket ARN without a role."
  }

  assert {
    condition     = length(module.log_group) == 0 && length(module.role) == 0 && output.log_group_name == null
    error_message = "S3 flow logs create no log group or role."
  }
}

run "flow_logs_off" {
  command = plan

  variables {
    flow_logs = { enabled = false }
  }

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(module.log_group) == 0 && output.flow_log_id == null
    error_message = "flow_logs.enabled = false creates no flow log."
  }
}

run "vpc_endpoints" {
  command   = apply
  state_key = "endpoints"

  variables {
    vpc_endpoints = {
      s3        = { type = "Gateway" }
      "ecr.api" = {}
      ssm       = { subnet_tier = "intra", policy_statements = [{ actions = ["ssm:GetParameter"], conditions = [{ test = "StringEquals", variable = "aws:PrincipalAccount", values = ["123456789012"] }] }] }
    }
  }

  assert {
    condition     = aws_vpc_endpoint.this["s3"].service_name == "com.amazonaws.eu-west-1.s3" && length(aws_vpc_endpoint.this["s3"].route_table_ids) == 4
    error_message = "Gateway endpoints attach to the private and intra route tables."
  }

  assert {
    condition     = aws_vpc_endpoint.this["ecr.api"].vpc_endpoint_type == "Interface" && aws_vpc_endpoint.this["ecr.api"].private_dns_enabled && toset(aws_vpc_endpoint.this["ecr.api"].subnet_ids) == toset(output.private_subnet_ids) && toset(aws_vpc_endpoint.this["ssm"].subnet_ids) == toset(output.intra_subnet_ids)
    error_message = "Interface endpoints use the subnets of their tier."
  }

  assert {
    condition     = toset(aws_vpc_endpoint.this["ecr.api"].security_group_ids) == toset([module.endpoint_security_group[0].id]) && keys(module.endpoint_security_group[0].ingress_rule_ids) == ["vpc"] && length(module.endpoint_security_group[0].egress_rule_ids) == 0
    error_message = "Interface endpoints get one security group: HTTPS from the VPC, no egress."
  }

  assert {
    condition     = aws_vpc_endpoint.this["ssm"].policy == module.endpoint_policy["ssm"].json && jsondecode(module.endpoint_policy["ssm"].json).Statement[0].Principal == { AWS = ["*"] } && jsondecode(module.endpoint_policy["ssm"].json).Statement[0].Resource == ["*"] && keys(module.endpoint_policy) == ["ssm"]
    error_message = "policy_statements render the endpoint policy with principal * by default."
  }

  assert {
    condition     = keys(output.vpc_endpoint_ids) == ["ecr.api", "s3", "ssm"] && output.vpc_endpoint_security_group_id == module.endpoint_security_group[0].id
    error_message = "Endpoint IDs are exported by service key."
  }
}

run "bring_your_own_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/flow-logs" }
  }

  assert {
    condition     = length(module.role) == 0 && aws_flow_log.this[0].iam_role_arn == "arn:aws:iam::123456789012:role/flow-logs"
    error_message = "A caller role must replace the module role."
  }
}

run "extend_the_role" {
  command = plan

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "Extra", actions = ["logs:DescribeLogGroups"], resources = ["*"] }]
    }
  }

  assert {
    condition     = contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "Extra") && contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "WriteFlowLogs")
    error_message = "Caller statements are added to the module statements."
  }
}

run "dhcp_options" {
  command = plan

  variables {
    dhcp_options = { enabled = true, domain_name = "corp.example.com" }
  }

  assert {
    condition     = aws_vpc_dhcp_options.this[0].domain_name == "corp.example.com" && aws_vpc_dhcp_options.this[0].domain_name_servers == tolist(["AmazonProvidedDNS"]) && length(aws_vpc_dhcp_options_association.this) == 1
    error_message = "DHCP options are created and associated when enabled."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Main_VPC"
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

run "rejects_invalid_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/8"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_small_cidr_with_computed_subnets" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/24"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_invalid_az_count" {
  command = plan

  variables {
    az_count = 7
  }

  expect_failures = [var.az_count]
}

run "rejects_duplicate_azs" {
  command = plan

  variables {
    azs = ["eu-west-1a", "eu-west-1a"]
  }

  expect_failures = [var.azs]
}

run "rejects_public_cidr_count" {
  command = plan

  variables {
    public_subnets = { cidrs = ["10.0.240.0/24"] }
  }

  expect_failures = [var.public_subnets]
}

run "rejects_public_cidr_format" {
  command = plan

  variables {
    azs            = ["eu-west-1a"]
    public_subnets = { cidrs = ["10.0.240.0"] }
  }

  expect_failures = [var.public_subnets]
}

run "rejects_private_cidr_count" {
  command = plan

  variables {
    private_subnets = { cidrs = ["10.0.0.0/20"] }
  }

  expect_failures = [var.private_subnets]
}

run "rejects_private_cidr_format" {
  command = plan

  variables {
    azs             = ["eu-west-1a"]
    private_subnets = { cidrs = ["private"] }
  }

  expect_failures = [var.private_subnets]
}

run "rejects_intra_cidr_count" {
  command = plan

  variables {
    intra_subnets = { cidrs = ["10.0.224.0/24"] }
  }

  expect_failures = [var.intra_subnets]
}

run "rejects_intra_cidr_format" {
  command = plan

  variables {
    azs           = ["eu-west-1a"]
    intra_subnets = { cidrs = ["intra"] }
  }

  expect_failures = [var.intra_subnets]
}

run "rejects_invalid_nat_mode" {
  command = plan

  variables {
    nat = { mode = "regional" }
  }

  expect_failures = [var.nat]
}

run "rejects_nat_without_public_subnets" {
  command = plan

  variables {
    public_subnets = { enabled = false }
  }

  expect_failures = [var.nat]
}

run "rejects_invalid_nacl_tier" {
  command = plan

  variables {
    nacl_rules = { x = { tier = "dmz", rule_number = 120, cidr_block = "10.0.0.0/8" } }
  }

  expect_failures = [var.nacl_rules]
}

run "rejects_invalid_nacl_action" {
  command = plan

  variables {
    nacl_rules = { x = { tier = "public", rule_number = 120, action = "reject", cidr_block = "10.0.0.0/8" } }
  }

  expect_failures = [var.nacl_rules]
}

run "rejects_nacl_without_one_cidr" {
  command = plan

  variables {
    nacl_rules = { x = { tier = "public", rule_number = 120 } }
  }

  expect_failures = [var.nacl_rules]
}

run "rejects_duplicate_nacl_rules" {
  command = plan

  variables {
    nacl_rules = {
      a = { tier = "public", rule_number = 120, cidr_block = "10.0.0.0/8" }
      b = { tier = "public", rule_number = 120, cidr_block = "10.1.0.0/16" }
    }
  }

  expect_failures = [var.nacl_rules]
}

run "rejects_rdp_from_internet" {
  command = plan

  variables {
    nacl_rules = { rdp = { tier = "public", rule_number = 120, cidr_block = "0.0.0.0/0", from_port = 3000, to_port = 4000 } }
  }

  expect_failures = [var.nacl_rules]
}

run "rejects_invalid_route_tier" {
  command = plan

  variables {
    routes = { x = { tiers = ["dmz"], destination_cidr_block = "10.100.0.0/16", transit_gateway_id = "tgw-0123456789abcdef0" } }
  }

  expect_failures = [var.routes]
}

run "rejects_route_with_two_destinations" {
  command = plan

  variables {
    routes = { x = { destination_cidr_block = "10.100.0.0/16", destination_prefix_list_id = "pl-0123456789abcdef0", transit_gateway_id = "tgw-0123456789abcdef0" } }
  }

  expect_failures = [var.routes]
}

run "rejects_route_without_target" {
  command = plan

  variables {
    routes = { x = { destination_cidr_block = "10.100.0.0/16" } }
  }

  expect_failures = [var.routes]
}

run "rejects_invalid_flow_log_destination" {
  command = plan

  variables {
    flow_logs = { destination = "firehose" }
  }

  expect_failures = [var.flow_logs]
}

run "rejects_s3_flow_logs_without_bucket" {
  command = plan

  variables {
    flow_logs = { destination = "s3" }
  }

  expect_failures = [var.flow_logs]
}

run "rejects_invalid_traffic_type" {
  command = plan

  variables {
    flow_logs = { traffic_type = "SOME" }
  }

  expect_failures = [var.flow_logs]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/vpc" }
  }

  expect_failures = [var.kms]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_endpoint_type" {
  command = plan

  variables {
    vpc_endpoints = { s3 = { type = "GatewayLoadBalancer" } }
  }

  expect_failures = [var.vpc_endpoints]
}

run "rejects_endpoint_in_disabled_tier" {
  command = plan

  variables {
    intra_subnets = { enabled = false }
    vpc_endpoints = { ssm = { subnet_tier = "intra" } }
  }

  expect_failures = [var.vpc_endpoints]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["nat-eu-west-1a-error-port-allocation", "nat-eu-west-1a-packets-drop-rate"])
    error_message = "Default alarms: port allocation errors and dropped packets on the single NAT gateway."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-nat-")]) && module.alarms[0].alarm_settings["nat-eu-west-1a-packets-drop-rate"].threshold == 0.01
    error_message = "Alarm names start with the module base name; dropped packets above 0.01 %."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        error_port_allocation = { threshold = 10 }
        packets_drop_rate     = { enabled = false }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["nat-eu-west-1a-error-port-allocation"])
    error_message = "A disabled alarm is dropped."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["nat-eu-west-1a-error-port-allocation"].threshold == 10 && module.alarms[0].alarm_settings["nat-eu-west-1a-error-port-allocation"].evaluation_periods == 15
    error_message = "Overrides change one setting; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["nat-eu-west-1a-error-port-allocation"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_per_az_nat" {
  command = plan

  variables {
    nat = { mode = "per_az" }
  }

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["nat-eu-west-1a-error-port-allocation", "nat-eu-west-1a-packets-drop-rate", "nat-eu-west-1b-error-port-allocation", "nat-eu-west-1b-packets-drop-rate", "nat-eu-west-1c-error-port-allocation", "nat-eu-west-1c-packets-drop-rate"])
    error_message = "per_az gives each NAT gateway its own alarms, keyed by AZ."
  }
}

run "alarms_without_nat" {
  command = plan

  variables {
    nat = { mode = "none" }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 0
    error_message = "Without NAT gateways there are no NAT alarms."
  }
}

run "alarms_plan_with_unknown_arns" {
  command   = plan
  state_key = "alarms_unknown_arns"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 2
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
