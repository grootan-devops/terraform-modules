# State migration

A change that moves a resource address, or changes a default or a provider version, can
replace or destroy live infrastructure. No static check proves it cannot; the plan of a
representative consumer does. Record the actions consumers must take in
[MIGRATION.md](../MIGRATION.md) for the release.

## Find the candidates

Diff the module's variables, outputs and resource addresses against the last release. A
removed variable, output or uncovered address is a MAJOR candidate. Two cases need judgement,
not a text diff:

- **A rename that looks like a delete plus an add** — `aws_s3_bucket.main` disappears and
  `aws_s3_bucket.this` appears. Map them only after confirming against state.
- **A re-key, not a rename** — converting `count` to `for_each` keeps the type and label but
  changes every index, so one `moved` block is needed per existing key, and the keys come from
  the consumer's current state, not from the source.

Changed defaults, instance keys, lifecycle settings and provider behaviour can replace an
object even when no address changes.

## Record the move

```hcl
moved {
  from = aws_s3_bucket.main
  to   = aws_s3_bucket.this
}
```

Keep moves in `moved.tf`, one block per verified address pair. A moved block maps an address;
it does not stop a replacement caused by a changed argument.

## Gate the release

1. With a representative consumer configuration and state, create a saved plan.
2. Inspect it and `terraform show -json <plan-file>`: every `resource_changes[].change.actions`
   containing `delete`, its `replace_paths`, and each `previous_address` from a move.
3. Investigate every replacement or deletion, and document the verified mapping or the
   required consumer action in the release's `MIGRATION.md` entry.
4. Keep the plan file out of Git; it can contain sensitive values.

Applying a change is a separate decision: confirm the exact account, workspace and environment,
review the saved plan's replacements and deletions, apply that saved plan, and re-plan if
configuration or state changes. Destroy and direct state commands need their own review.

[Documentation index](../README.md#documentation)
