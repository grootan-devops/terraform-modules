# AWS VPC Module

The `vpc` module provisions production-grade AWS Virtual Private Clouds (VPCs) with multi-tier subnet architectures (Public, Private, Intra), NAT Gateway topologies, Network ACLs, and automated VPC Flow Logs.

### Architecture & Managed Resources
- `aws_vpc.main`: Core VPC with DNS hostnames and resolution enabled.
- `aws_subnet.public`: Public ingress subnets with Internet Gateway route tables.
- `aws_subnet.private`: Private application subnets routed through NAT Gateways.
- `aws_subnet.intra`: Isolated database/storage subnets without external Internet access.
- `aws_flow_log.this`: Captures `ALL` traffic to a dedicated KMS-encrypted CloudWatch log group.
- `aws_vpc_endpoint`: Gateway and Interface private endpoints to keep AWS API traffic off the public internet.

### Security & Compliance Guardrails
- **Mandatory Flow Logs Encryption**: CloudWatch log group encrypted with mandatory `kms_key_arn` and 90-day retention.
- **CIDR Block Validation**: Strictly validated with `cidrnetmask` to prevent invalid IPv4 prefix allocations.
- **Subnet Tier Isolation**: Dedicated route tables and Network ACLs per tier prevent unexpected cross-tier exposure.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "network"

  cidr_block                  = "10.0.0.0/16"
  aws_availability_zone_names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs        = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example
```hcl
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=1.0.0"

  application = "enterprise"
  environment = "prod"
  name        = "primary-vpc"

  cidr_block                  = "10.200.0.0/16"
  aws_availability_zone_names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs         = ["10.200.1.0/24", "10.200.2.0/24", "10.200.3.0/24"]
  private_subnet_cidrs        = ["10.200.10.0/24", "10.200.20.0/24", "10.200.30.0/24"]
  intra_subnet_cidrs          = ["10.200.100.0/24", "10.200.200.0/24", "10.200.300.0/24"]

  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  cloudwatch_logs = {
    enabled           = true
    exports           = ["vpc_flow"]
    retention_in_days = { vpc_flow = 90 }
    kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  vpc_endpoints = {
    enabled                   = true
    services                  = ["s3", "dynamodb", "secretsmanager", "ecr.api", "ecr.dkr", "logs"]
    gateway_route_table_tiers = ["private", "intra"]
    interface_subnet_tier     = "private"
    private_dns_enabled       = true
  }

  tags = {
    NetworkZone = "CoreTransit"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Name for the VPC. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `application` | Logical application or product name used for resource naming and tagging | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `cidr_block` | CIDR block for the VPC (e.g. 172.31.0.0/16) | `string` | **Required** | Yes |
| `aws_availability_zone_names` | List of AWS availability zone names to distribute subnets across | `list(string)` | **Required** | Yes |
| `public_subnet_cidrs` | CIDR blocks for public subnets, one per availability zone | `list(string)` | **Required** | Yes |
| `private_subnet_cidrs` | CIDR blocks for private subnets with outbound internet access via NAT Gateway | `list(string)` | **Required** | Yes |
| `intra_subnet_cidrs` | CIDR blocks for intra subnets with no outbound internet access | `list(string)` | **Required** | Yes |
| `private_subnet_internet_gateway` | If true, routes 0.0.0.0/0 in private subnets to the Internet Gateway instead of a NAT Gateway (requires instances to have public IPs). | `bool` | `false` | No |
| `intra_subnet_internet_gateway` | If true, routes 0.0.0.0/0 in intra subnets to the Internet Gateway. | `bool` | `false` | No |
| `dns` |  | `object({...})` | `{}` | No |
| `nat` |  | `object({...})` | `{}` | No |
| `dhcp_options` |  | `object({...})` | `{}` | No |
| `cloudwatch_logs` |  | `object({...})` | `{...}` | No |
| `vpc_endpoints` |  | `object({...})` | `{}` | No |
| `nacl` |  | `object({...})` | `{}` | No |
| `additional_routes` |  | `object({...})` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting VPC Flow Logs in CloudWatch. Strictly required. | `string` | **Required** | Yes |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `vpc_id` | The ID of the VPC | No |
| `cidr_block` | The CIDR block of the VPC | No |
| `public_subnets` | List of IDs of public subnets | No |
| `private_subnets` | List of IDs of private subnets | No |
| `intra_subnets` | List of IDs of intra subnets | No |

