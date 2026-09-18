# AWS DynamoDB Table Module

The `dynamodb` module manages Amazon DynamoDB NoSQL tables featuring Global Secondary Indexes (GSIs), Local Secondary Indexes (LSIs), Point-in-Time Recovery (PITR), and Customer Managed KMS Key encryption.

### Architecture & Managed Resources
- `aws_dynamodb_table.this`: Primary DynamoDB table definition.
- `aws_dynamodb_contributor_insights.this`: Optional CloudWatch Contributor Insights monitoring.

### Security & Compliance Guardrails
- **Mandatory KMS CMK**: Server-side encryption strictly enforced with `kms_key_arn`.
- **Point-in-Time Recovery**: Continuous backup enabled by default (`pitr_recovery_period_in_days = 35`).
- **Deletion Protection**: Enabled by default (`deletion_protection_enabled = true`).

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
module "dynamodb" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/database/dynamodb"

  application  = "core"
  environment  = "prod"
  name         = "sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  table_class  = "STANDARD"
  kms_key_arn  = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  attributes = [
    { name = "session_id", type = "S" }
  ]
}
```

### Complete Production Example
```hcl
module "dynamodb" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/database/dynamodb"

  application  = "orders"
  environment  = "prod"
  name         = "ledger"
  billing_mode = "PAY_PER_REQUEST"
  table_class  = "STANDARD"
  hash_key     = "account_id"
  range_key    = "order_id"

  kms_key_arn                  = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  deletion_protection_enabled  = true
  pitr_recovery_period_in_days = 35
  enable_contributor_insights  = true

  attributes = [
    { name = "account_id", type = "S" },
    { name = "order_id", type = "S" },
    { name = "status", type = "S" },
    { name = "created_at", type = "N" }
  ]

  global_secondary_indexes = [
    {
      name            = "gsi_status_created"
      hash_key        = "status"
      range_key       = "created_at"
      projection_type = "ALL"
    }
  ]

  stream = {
    enabled   = true
    view_type = "NEW_AND_OLD_IMAGES"
  }

  tags = {
    Compliance = "SOC2-Type-II"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | The name of the table | `string` | **Required** | Yes |
| `billing_mode` | Controls how you are charged for read and write throughput and how you manage capacity. Valid values are PROVISIONED and PAY_PER_REQUEST. | `string` | **Required** | Yes |
| `hash_key` | The attribute to use as the hash (partition) key. Must also be defined as an attribute. | `string` | **Required** | Yes |
| `range_key` | The attribute to use as the range (sort) key. Must also be defined as an attribute. | `string` | `null` | No |
| `attributes` | List of nested attribute definitions. Only required for hash_key and range_key attributes. | `list(object({...}))` | `[]` | No |
| `read_capacity` | Number of read units for this table. If the billing_mode is PROVISIONED, this field is required. | `number` | `null` | No |
| `write_capacity` | Number of write units for this table. If the billing_mode is PROVISIONED, this field is required. | `number` | `null` | No |
| `table_class` | The storage class of the table. Valid values are STANDARD and STANDARD_INFREQUENT_ACCESS. | `string` | **Required** | Yes |
| `on_demand_throughput` | Sets the maximum number of read and write units for the specified on-demand table. | `object({...})` | `null` | No |
| `warm_throughput` | Provides visibility into the warm throughput configuration of the table. | `object({...})` | `null` | No |
| `global_table_witness` | Witness Region in a Multi-Region Strong Consistency deployment. | `object({...})` | `null` | No |
| `kms_key_arn` | ARN of the KMS key for server-side encryption. | `string` | **Required** | Yes |
| `pitr_recovery_period_in_days` | Number of days to keep point-in-time recovery data. | `number` | **Required** | Yes |
| `stream` | Stream options. | `object({...})` | `{ enabled = false view_type = null }` | No |
| `global_secondary_indexes` | Describe a GSI for the table | `list(object({...}))` | `[]` | No |
| `local_secondary_indexes` | Describe an LSI on the table; these can only be allocated at creation. | `list(object({...}))` | `[]` | No |
| `replicas` | Configuration for aws_dynamodb_table_replica resources. | `map(object({...}))` | `{}` | No |
| `enable_contributor_insights` | Enable CloudWatch contributor insights for the table | `bool` | **Required** | Yes |
| `contributor_insights_index_name` | The global secondary index name for contributor insights, if applicable | `string` | `null` | No |
| `application` | Name of the product | `string` | **Required** | Yes |
| `deletion_protection_enabled` | Enable deletion protection on the DynamoDB table | `bool` | `true` | No |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `table_name` | DynamoDB table name. | No |
| `table_arn` | DynamoDB table ARN. | No |

