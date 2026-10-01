# Provider schema

Design a module's inputs and outputs from the provider's machine-readable schema, not from web
documentation, which shows the latest provider and describes nested blocks loosely. The schema
gives exact types, marks `sensitive` and `computed` attributes, and exposes write-only
arguments (such as `secret_string_wo`). It proves which arguments exist; it does not prove
runtime behaviour or migration safety — replacement decisions come from a representative plan
(see [State migration](state-migration.md)).

## Extract it

```bash
terraform -chdir=<module_directory> init -backend=false
terraform -chdir=<module_directory> providers schema -json > /tmp/provider_schema.json
```

The output is keyed by provider, then resource type:

```json
{
  "provider_schemas": {
    "registry.terraform.io/hashicorp/aws": {
      "resource_schemas": {
        "aws_s3_bucket": {
          "block": {
            "attributes": {
              "bucket": { "type": "string", "optional": true, "computed": true },
              "force_destroy": { "type": "bool", "optional": true }
            },
            "block_types": {
              "cors_rule": { "nesting_mode": "list", "block": {} }
            }
          }
        }
      }
    }
  }
}
```

## Map it to variables and outputs

| Schema type | Variable type |
| --- | --- |
| `"string"` | `string` |
| `"number"` | `number` |
| `"bool"` | `bool` |
| `["list", "string"]` | `list(string)` |
| `["map", "string"]` | `map(string)` |
| `["set", "string"]` | `set(string)` |
| `block_types` with `nesting_mode: "list"` | `list(object({...}))` |
| `block_types` with `nesting_mode: "single"` | `object({...})` |

- `"required": true` maps to a required variable without a default, or to an opinionated
  module default.
- `"computed": true` without `"optional"` is read-only: never a variable; an output when it
  is useful to callers.
- `"sensitive": true` means the variable or output mapped to it is `sensitive = true`.
- An argument absent from the schema is never invented — see the capability statuses in the
  README §6.1.

[Documentation index](../README.md#documentation)
