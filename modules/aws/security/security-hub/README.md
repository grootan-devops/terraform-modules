# AWS Security Hub CSPM Module

Scope: `account`

Security Hub CSPM for an AWS organization with central configuration. Called twice: from the management account to
designate the delegated administrator, and from that administrator in the home Region (the provider Region) for the
hub, cross-Region finding aggregation, the `CENTRAL` organization configuration, configuration policies and their
associations. Central configuration applies the policies in the home Region and every linked Region, so `regions`
stays empty.

With `organization_configuration.enabled = false` the module runs in account-only mode for a standalone account, or a
management account that is also the workload account: the hub in the home Region and every Region of `regions`, the
selected standards subscribed in each of them, the finding aggregator and product subscriptions, without central
configuration.

## Architecture & Managed Resources

- `aws_securityhub_organization_admin_account.this` (`organization_admin.enabled`, management account): designates the
  delegated administrator, which also enables trusted access; central configuration then uses it in every linked Region.
- `aws_securityhub_account.this` (`hub.enabled`): one per Region (the home Region, plus `regions` in account-only
  mode), no default standards, consolidated control findings (`SECURITY_CONTROL`), new controls enabled automatically.
- `aws_securityhub_standards_subscription.this` (account-only mode): each selected standard in each hub Region, keyed
  `<region>/<standard key>`, with that Region's standards ARN.
- `aws_securityhub_finding_aggregator.this`: `ALL_REGIONS` by default.
- `aws_securityhub_organization_configuration.this` (`organization_configuration.enabled`): `CENTRAL`, no auto-enable.
- `aws_securityhub_configuration_policy.this`: one per `configuration_policies` entry that has `targets`, named
  `<application>-<environment>-<key>`; the default `baseline` entry creates nothing until it gets targets.
- `aws_securityhub_configuration_policy_association.this`: one per target, keyed `<policy key>/<index>` (or
  `SELF_MANAGED_SECURITY_HUB/<index>` for `self_managed_targets`), so target IDs may be unknown at plan.
- `aws_securityhub_product_subscription.this`: third-party products in `product_subscriptions`.

No Security Hub CSPM resource has a `tags` argument in `hashicorp/aws` 6.73.0, so `tags` reaches nothing yet.

## Security & Compliance Guardrails

- **Modes:** `organization_configuration.enabled = true` (default) enables standards through central configuration
  policies from the delegated administrator; `false` (account-only mode) subscribes them in this account's hub
  Regions and rejects policy targets and `self_managed_targets`.
- **Standards:** FSBP v1.0.0, CIS v5.0.0, NIST SP 800-171 r2, AWS Resource Tagging, PCI DSS v4.0.1 and AI Security are
  on by default; NIST SP 800-53 r5, CIS v3.0.0, v1.4.0, v1.2.0 and PCI DSS v3.2.1 are opt-in through `standards` (a
  policy's own `standards` override them); other standards through a policy's `additional_standard_arns`
  (service-managed ones are rejected).
- **CRI Profile v2.2:** AWS has not published its ARN; it is enabled only with `cri_profile = { enabled = true,
  standard_arn = ... }` (`aws securityhub describe-standards`). Account-only mode puts each hub Region in the ARN.
- **Controls:** every control stays enabled, new ones included, unless listed in `disabled_control_identifiers`;
  `enabled_control_identifiers` enables only the listed controls.
- **One governing policy per target:** a root, OU or account appears once across policies and `self_managed_targets`.
- **Administrator separation:** the management account cannot be the administrator, and `organization_admin` cannot
  run in the same call as central configuration.
- **Encryption and IAM:** Security Hub CSPM encrypts its data with AWS owned keys and creates its own service-linked
  role; no key or IAM policy is managed here.
- **Findings need AWS Config** recording in every account and linked Region ([`security/config`](../config)).

Designating the administrator enables Security Hub CSPM in that account, so import
`aws_securityhub_account.this["<home Region>"]` (ID = account ID) before the first apply there. While central
configuration is in use the administrator cannot be removed through Security Hub CSPM.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "security_hub_admin" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/security-hub?ref=<version>"

  environment        = "prod"
  hub                = { enabled = false }
  organization_admin = { enabled = true, account_id = "222222222222" }
}

module "security_hub" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/security-hub?ref=<version>"

  environment = "prod"
  configuration_policies = {
    baseline = { targets = [module.organizations.root_id] }
  }
}
```

### Complete Production Example

```hcl
module "security_hub" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/security-hub?ref=<version>"

  environment              = "prod"
  finding_aggregator       = { linking_mode = "ALL_REGIONS_EXCEPT_SPECIFIED", specified_regions = ["ap-east-1"] }
  cri_profile              = { enabled = true, standard_arn = var.cri_profile_standard_arn }

  configuration_policies = {
    baseline = {
      targets = [module.organizations.root_id]
      custom_parameters = [{
        security_control_id = "IAM.7"
        parameters          = [{ name = "MaxPasswordAge", int = 90 }]
      }]
    }
    regulated = {
      standards = { nist_800_53_r5 = true, pci_v3_2_1 = true }
      targets   = [var.regulated_ou_id]
    }
    sandbox = {
      service_enabled = false
      targets         = [var.sandbox_ou_id]
    }
  }

  self_managed_targets  = ["333333333333"]
  product_subscriptions = ["arn:aws:securityhub:us-east-1:517716713836:product/crowdstrike/crowdstrike-falcon"]
}
```

### Account-only Mode Example

A standalone account, or a management account with no delegated administrator:

```hcl
module "security_hub" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/security-hub?ref=<version>"

  environment                = "prod"
  regions                    = ["us-east-1"]
  organization_configuration = { enabled = false }
  standards                  = { nist_800_53_r5 = true }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Account-only mode: more Regions for the hub and standards. | `list(string)` | `[]` | No |
| `hub` | Hub, aggregator and standards in this account. | `object({...})` | `{}` | No |
| `organization_admin` | Management account call: delegated administrator. | `object({...})` | `{}` | No |
| `finding_aggregator` | Cross-Region aggregation into the provider Region. | `object({...})` | `{}` | No |
| `organization_configuration` | Central configuration: policies and associations; off for account-only mode. | `object({...})` | `{}` | No |
| `standards` | Standards on or off by key, over the defaults; policies override. | `map(bool)` | `{}` | No |
| `configuration_policies` | Configuration policies by key; created only with targets. | `map(object({...}))` | `{...}` | No |
| `self_managed_targets` | Root, OU or account IDs set to self-managed. | `list(string)` | `[]` | No |
| `cri_profile` | CRI Profile v2.2 and its StandardsArn; off leaves CRI out. | `object({...})` | `{}` | No |
| `product_subscriptions` | Third-party product ARNs to accept findings from. | `list(string)` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Hub ARN; null when the hub is off. | No |
| `finding_aggregator_arn` | Finding aggregator ARN; null when the hub is off. | No |
| `configuration_policy_ids` | Configuration policy IDs by key. | No |
