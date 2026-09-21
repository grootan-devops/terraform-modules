# AWS ElastiCache Valkey Module

The `elasticache/valkey` module manages Valkey replication groups for low-latency caching and session persistence with mandatory in-transit TLS and at-rest KMS encryption.

## Architecture & Managed Resources

- `aws_elasticache_replication_group.this`: Valkey cluster instances.
- `aws_elasticache_subnet_group.this`: VPC cache subnet placement.
- `aws_elasticache_parameter_group.this`: Engine parameter tuning.
- `aws_security_group.this`: Firewall controlling ingress to port 6379.

### Security & Compliance Guardrails

- **Mandatory In-Transit & At-Rest Encryption**: `transit_encryption_enabled = true` and `at_rest_encryption_enabled = true` enforced.
- **Mandatory KMS CMK**: Data at rest encrypted via Customer Managed Key (`kms_key_id`).
- **Isolated Network Placement**: Subnet group deployed exclusively across internal subnets.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example

```hcl
module "valkey" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/elasticache/valkey?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "cache"

  vpc_id     = "vpc-0a1b2c3d4e5f67890"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "valkey" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/elasticache/valkey?ref=1.0.0"

  application = "session"
  environment = "prod"
  name        = "cluster"

  vpc_id              = "vpc-0a1b2c3d4e5f67890"
  subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id          = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  node_type           = "cache.r7g.large"
  num_cache_clusters  = 3
  allowed_cidr_blocks = ["10.0.0.0/16"]

  parameters = [
    {
      name  = "maxmemory-policy"
      value = "allkeys-lru"
    }
  ]

  tags = {
    CacheTier = "DistributedSession"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | The name of the Valkey cluster | `string` | `null` | No |
| `application` | The name of the product/application | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `tags` | A mapping of tags to assign to the resources | `map(string)` | `{}` | No |
| `engine_version` | The version number of the cache engine to be used | `string` | `"9.0"` | No |
| `node_type` | The compute and memory capacity of the nodes | `string` | `"cache.t4g.micro"` | No |
| `num_cache_clusters` | The number of cache clusters (primary and replicas) this replication group will have | `number` | `1` | No |
| `parameter_group_family` | The family of the ElastiCache parameter group | `string` | `"valkey9"` | No |
| `parameters` | A list of ElastiCache parameters to apply to the parameter group | `list(object({...}))` | `[]` | No |
| `subnet_ids` | A list of VPC subnet IDs for the cache subnet group | `list(string)` | **Required** | Yes |
| `vpc_id` | The VPC ID where the security group should be created | `string` | **Required** | Yes |
| `allowed_cidr_blocks` | List of CIDR blocks allowed to access the Valkey cluster | `list(string)` | `[]` | No |
| `egress_cidr_blocks` | List of CIDR blocks allowed for outbound traffic from the Valkey cluster | `list(string)` | `["0.0.0.0/0"]` | No |
| `port` | The port number on which each of the cache nodes accepts connections | `number` | `6379` | No |
| `kms_key_id` | The ARN of the KMS key to use for encrypting data at rest | `string` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `primary_endpoint_address` | The DNS endpoint of the primary node in the replication group | No |
| `reader_endpoint_address` | The DNS endpoint of the reader node(s) in the replication group | No |
| `configuration_endpoint_address` | The configuration endpoint address for cluster mode | No |
