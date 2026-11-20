output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "VPC ARN."
  value       = aws_vpc.this.arn
}

output "cidr_block" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability Zones in subnet order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ."
  value       = [for k, s in local.subnets : aws_subnet.this[k].id if s.tier == "public"]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ."
  value       = [for k, s in local.subnets : aws_subnet.this[k].id if s.tier == "private"]
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs, one per AZ."
  value       = [for k, s in local.subnets : aws_subnet.this[k].id if s.tier == "intra"]
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  value       = [for s in values(local.subnets) : s.cidr if s.tier == "public"]
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  value       = [for s in values(local.subnets) : s.cidr if s.tier == "private"]
}

output "intra_subnet_cidrs" {
  description = "Intra subnet CIDRs."
  value       = [for s in values(local.subnets) : s.cidr if s.tier == "intra"]
}

output "public_route_table_ids" {
  description = "Public route table IDs."
  value       = [for k, t in local.route_tables : aws_route_table.this[k].id if t == "public"]
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ."
  value       = [for k, t in local.route_tables : aws_route_table.this[k].id if t == "private"]
}

output "intra_route_table_ids" {
  description = "Intra route table IDs."
  value       = [for k, t in local.route_tables : aws_route_table.this[k].id if t == "intra"]
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = [for k in local.nat_keys : aws_nat_gateway.this[k].id]
}

output "nat_public_ips" {
  description = "NAT gateway public IPs."
  value       = [for k in local.nat_keys : aws_eip.nat[k].public_ip]
}

output "vpc_endpoint_ids" {
  description = "VPC endpoint IDs by service key."
  value       = { for k, e in aws_vpc_endpoint.this : k => e.id }
}

output "vpc_endpoint_security_group_id" {
  description = "Interface endpoint security group ID; null without one."
  value       = one(module.endpoint_security_group[*].id)
}

output "flow_log_id" {
  description = "Flow log ID; null when disabled."
  value       = one(aws_flow_log.this[*].id)
}

output "log_group_name" {
  description = "Flow log group name; null unless cloudwatch."
  value       = one(module.log_group[*].name)
}

output "log_group_arn" {
  description = "Flow log group ARN; null unless cloudwatch."
  value       = one(module.log_group[*].arn)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
