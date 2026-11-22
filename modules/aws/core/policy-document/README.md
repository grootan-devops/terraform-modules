# Policy Document Helper

Scope: `helper`

Renders the library's typed `policy_statements` into IAM or resource policy JSON. No provider and no resources, so
tests read every statement offline.

## Architecture & Managed Resources

- None. Pure function of its inputs.

## Security & Compliance Guardrails

- Rejects `Allow` for principal `*` without a condition unless `allow_public = true`.
- Groups conditions by operator; drops empty `Sid`, `Principal` and `Condition`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "policy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/policy-document?ref=<version>"

  statements = [{ actions = ["sqs:SendMessage"], resources = ["arn:aws:sqs:eu-west-1:111122223333:orders"] }]
}
```

### Complete Production Example

```hcl
module "policy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/policy-document?ref=<version>"

  default_resources = ["arn:aws:sqs:eu-west-1:111122223333:orders"]
  source_documents  = [jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "sqs:*", Resource = "*", Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })]
  statements = [{
    sid        = "AllowEventBridge"
    actions    = ["sqs:SendMessage"]
    principals = { Service = ["events.amazonaws.com"] }
    conditions = [{ test = "ArnEquals", variable = "aws:SourceArn", values = ["arn:aws:events:eu-west-1:111122223333:rule/orders"] }]
  }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `statements` | Typed policy statements. | `list(object({...}))` | `[]` | No |
| `default_resources` | Resources for statements without resources. | `list(string)` | `[]` | No |
| `source_documents` | Policy JSON documents placed first. | `list(string)` | `[]` | No |
| `allow_public` | Allow principal * without a condition. | `bool` | `false` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `json` | Policy JSON. | No |
| `statements_json` | Rendered statements as a JSON list. | No |
| `statement_count` | Statement count. | No |
