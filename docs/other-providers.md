# Other providers

This library ships AWS modules. A module for another cloud follows the same contract, naming
and capability rules, with the provider's own limits. The rows below are a starting point:
confirm each against `terraform providers schema -json` before relying on it.

## Naming bounds

Truncate to `limit - (hash + 1)` characters and append a hyphen and a stable hash of the full
name (README §5.2), against the provider's bounds:

| Provider | Resource | Limit | Valid characters | Mitigation |
| --- | --- | :---: | --- | --- |
| Azure | `azurerm_storage_account` | 3–24 | lowercase alphanumeric only, no hyphens | strip hyphens, lowercase, truncate to 18 + 6-character hash |
| Azure | `azurerm_virtual_network` | 2–64 | alphanumeric, `_`, `-`, `.` | truncate to 58 + 5-character hash |
| GCP | `google_compute_network` | 1–63 | lowercase, digits, hyphen | truncate to 57 + 5-character hash |

## Capability statuses

Classify each control from the schema with the procedure in README §6.1.

### Azure (`azurerm`)

| Resource | CMEK at rest | TLS ≥ 1.2 | Audit logging | Deletion protection | Public boundary |
| --- | :---: | :---: | :---: | :---: | :---: |
| `azurerm_storage_account` | `required` (Key Vault) | `required` (`min_tls_version`) | `required` (diagnostics) | `recommended` (management lock) | `required` (`public_network_access_enabled=false`) |
| `azurerm_postgresql_flexible_server` | `required` (Key Vault) | `required` (SSL enforcement) | `required` (audit logs) | `not_supported` (use a resource lock) | `required` (VNet delegation) |
| `azurerm_key_vault` | `required` (soft delete and purge protection) | `required` | `required` (diagnostics) | `required` (`purge_protection_enabled=true`) | `required` |
| `azurerm_virtual_network` | `not_applicable` | `not_applicable` | `required` (Network Watcher) | `not_applicable` | `required` (NSG deny) |

### GCP (`google`)

| Resource | CMEK at rest | TLS ≥ 1.2 | Audit logging | Deletion protection | Public boundary |
| --- | :---: | :---: | :---: | :---: | :---: |
| `google_storage_bucket` | `required` (Cloud KMS) | `provider_managed` | `recommended` | `recommended` (retention) | `required` (`uniform_bucket_level_access`) |
| `google_sql_database_instance` | `required` (Cloud KMS) | `required` (`require_ssl`) | `required` | `required` (`deletion_protection`) | `required` (`ipv4_enabled=false`) |
| `google_compute_network` | `not_applicable` | `not_applicable` | `required` (flow logs) | `not_applicable` | `required` (Private Google Access) |

AWS-specific rules do not transfer to another provider without schema evidence.

[Documentation index](../README.md#documentation)
