output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = [for s in aws_subnet.private : s.id]
}

output "intra_subnets" {
  description = "List of IDs of intra subnets"
  value       = [for s in aws_subnet.intra : s.id]
}
