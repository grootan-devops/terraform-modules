# Conventions

How configuration travels from the calling stack to a provider resource, and
the rules every area of this module follows. Read this before adding an area
(`modules/<area>/`) or a new input; the per-area READMEs assume it.

Two worked traces — one for a monitor, one for a status page — are in
[§4](#4-two-traces-end-to-end).

## 1. The five layers

Configuration is never read straight from a variable into a resource attribute.
It passes through fixed layers, each with one job.

| # | Layer | Path | Owns | Must not |
| --- | --- | --- | --- | --- |
| 1 | **Stack** | the calling stack's `locals.tf` and module block | *What* exists: monitors, pages, who owns what. Stack-wide `*_defaults` overrides | Contain resources, `try()`, or ids |
| 2 | **Contract** | `modules/oneuptime/variables-<area>.tf` | Types, the shipped defaults, **all** validation | Reference resources or locals |
| 3 | **Shared derivation** | `modules/oneuptime/locals.tf`, `labels.tf`, `teams.tf` | What *every* area needs: `component_definitions`, `label_ids`, `team_ids` | Know anything area-specific |
| 4 | **Area derivation** | `modules/<area>/locals.tf` | Merging defaults, flattening, generating. The real work | Declare types or validate |
| 5 | **Resources** | `modules/<area>/main.tf` | `for_each` over a layer-4 local, attributes assigned | Contain merge/precedence logic |

The rule that follows from this: **`main.tf` should read like a list of
assignments.** If a resource attribute contains a `merge()`, a nested `for`, or
more than one `try()`, it belongs in `locals.tf`. The monitors submodule is the
example — `monitor_steps = local.monitor_steps[each.key]` is one line because
the layering happens in [`modules/monitors/locals.tf`](modules/monitors/locals.tf)
and [`criteria.tf`](modules/monitors/criteria.tf).

### Why the parent owns labels and teams

`oneuptime_label` and `oneuptime_team` are created in layer 3, not in an area
submodule, because **every** area needs their ids. Layer 3 resolves them into
two flat maps and passes those down, so no submodule reaches back into a
resource it does not own:

```hcl
label_ids = { for name, label in oneuptime_label.this : name => label.id }
team_ids  = { for name, team in oneuptime_team.this : name => team.id }
```

The same rule decides where a **data source** lives: a lookup only one area
needs belongs to that area. Monitor statuses and severities sit in
[`modules/monitors/data.tf`](modules/monitors/data.tf); custom domains sit in
[`modules/status-pages/data.tf`](modules/status-pages/data.tf).

### Cross-area dependencies are data, never `depends_on`

`modules/status-pages` publishes what `modules/monitors` creates, so it takes
its ids as inputs in [`main.tf`](main.tf):

```hcl
monitor_ids       = module.monitors.monitor_ids
monitor_group_ids = module.monitors.monitor_group_ids
```

That is the only coupling between areas, and it makes the ordering implicit.

## 2. Two defaulting mechanisms

Both mean "the stack sets it once, an item overrides it where it differs".
Which one an area uses is decided by whether its entries are the same shape.

| | `merge()` layering | `coalesce()` per attribute |
| --- | --- | --- |
| Used by | monitors | status pages, on-call, alerts, incidents |
| Config type | `any` | `map(object({...}))` with `optional()` and **no** default |
| Entries are | heterogeneous — an API monitor and a Manual monitor share almost no keys | homogeneous — every page has the same attributes |
| "Not set" is | key absent, read with `try()` | attribute is `null` |
| Precedence | argument order — **later wins** | argument order — **first non-null wins** |
| Reads like | `merge(defaults, type_defaults, item, overrides)` | `coalesce(page.x, defaults.x)` |

Do not mix them within one area. If a new area's entries are the same shape,
type them properly and use `coalesce` — the typed form gives better errors and
`terraform-docs` output. Reach for `any` + `merge` only when entries genuinely
differ in shape, as monitors do across 30 monitor types.

### The `coalesce` form

Every overridable attribute in the config is `optional(bool)` — optional with
**no default**, so it is `null` unless the page actually sets it. The default
lives once, in `*_defaults`:

```hcl
// variables-status-pages.tf  - layer 2
show_uptime_history_in_days = optional(number, 90)   // in status_page_defaults
show_uptime_history_in_days = optional(number)       // in status_page_configs, no default

// modules/status-pages/locals.tf  - layer 4
show_uptime_history_in_days = coalesce(page.show_uptime_history_in_days, var.status_page_defaults.show_uptime_history_in_days)
```

Giving the attribute a default in *both* places is the mistake this guards
against: the page-level default would win and `status_page_defaults` would
silently do nothing.

### The `merge` form

```hcl
// modules/monitors/locals.tf  - layer 4
merge(
  local.monitor_step_defaults,                            // 1. stack baseline
  local.monitor_type_step_defaults[spec.monitor_type],     // 2. implied by the type
  { monitor_destination = spec.config.target },            // 3. the monitor's minimum
  spec.config.step,                                        // 4. the monitor's own overrides
  { criteria = local.monitor_criteria[key] },              // 5. generated, not overridable here
)
```

Read it top to bottom as lowest to highest precedence. Anything that must not
be overridable goes **last**, deliberately.

## 3. The precedence ladders

### Monitors — five levels

| # | Level | Where | Scope |
| --- | --- | --- | --- |
| 1 | Module default | `optional(number, 5000)` in [variables-monitors.tf](variables-monitors.tf) | every stack |
| 2 | Stack | `monitor_defaults.thresholds.response_time_ms` in the module block | every monitor in the stack |
| 3 | Monitor | `thresholds.response_time_ms` on the entry | every criterion of that monitor |
| 4 | Criterion | `criteria.degraded.response_time_ms` | that one criterion |
| 5 | Raw | `criteria.degraded.overrides` | merged over the finished criterion, after everything |

Level 3 exists because some values are read by more than one criterion —
a heartbeat window is compared by both the `offline` and the `operational`
criterion, so it cannot live on either of them.

Level 5 is the pressure valve: it takes raw provider fields and is merged last,
so it can set something the generator has no opinion about without a new input
being added to the module.

### Status pages — three levels, plus children

| # | Level | Where |
| --- | --- | --- |
| 1 | Module default | `optional(number, 90)` in [variables-status-pages.tf](variables-status-pages.tf) |
| 2 | Stack | `status_page_defaults.show_uptime_history_in_days` |
| 3 | Page | the page's entry in `status_page_configs` |

A page's **children** — groups, resources, subscribers, announcements — have
their own two-level ladder. The default lives in a sub-object of
`status_page_defaults` named after the child, and the child overrides it:

```hcl
status_page_defaults = {
  group    = { view_mode = "Grid" }        // every group of every page
  resource = { show_uptime_percent = false }
}
```

Note the asymmetry, which is deliberate rather than an oversight: there is no
per-page default for children. A page cannot say "all *my* groups are Grid" —
it is either stack-wide or set on each group. Add the middle level only if a
stack actually needs it.

## 4. Two traces, end to end

### A monitor threshold

`response_time_ms = 3000`, set on one criterion of one monitor.

| Layer | What happens |
| --- | --- |
| 1 | the stack's `locals.tf` — `criteria.degraded.response_time_ms = 3000` |
| 2 | `var.monitor_configs` (`any`) — validated: type known, `target` present |
| — | `main.tf` passes it to `module.monitors` |
| 4 | `local.monitor_specs["gitlab"]` — config read once, defaults resolved |
| 4 | `local.criteria_contexts` — `params = merge(param_defaults, spec.thresholds, criteria.degraded)` → `3000` wins |
| 4 | `local.http_criteria_filters[id].degraded` — becomes a filter, `value = tostring(3000)` |
| 4 | `local.criteria_rendered_presets[id]` — envelope built around those filters |
| 4 | `local.monitor_criteria["gitlab"]` — regrouped and ordered by preset |
| 4 | `local.generated_monitor_steps["gitlab"]` — criteria attached to the step |
| 5 | `oneuptime_monitor.this["gitlab"].monitor_steps[0].criteria[1].filters[1].value` |

Every string a filter compares is `tostring()`-ed at layer 4, because the
provider requires `value` to be a string even for numbers. A stack never
writes `"3000"`.

### A status page attribute

`show_uptime_history_in_days`, never set by the page.

| Layer | What happens |
| --- | --- |
| 2 | `optional(number, 90)` — the shipped default. Validated `1..90` |
| 1 | the page does not set it → `null` |
| 4 | `coalesce(null, 90)` → `90` in `local.status_page_definitions["core"]` |
| 5 | `oneuptime_status_page.this["core"].show_uptime_history_in_days = each.value.…` |

### Labels — the cross-cutting one

| Layer | What happens |
| --- | --- |
| 1 | `labels_config` in the module block; `application = "core"` |
| 3 | `local.project_labels_config` — merged with the auto `project` label |
| 3 | `oneuptime_label.this` — one per label name |
| 3 | `local.label_ids` — name → id |
| 4 | `local.monitor_definitions[*].label_names` — derived from `monitors_component_mapping`, never from `monitor_configs` |
| 5 | `oneuptime_monitor.this[*].labels` |

**Labels are never written on an item.** They are derived from the component
mapping, so labelling stays consistent and the owner/label rules keep matching.

## 5. Naming

| Pattern | Means | Examples |
| --- | --- | --- |
| `<area>_configs` | one entry per thing, keyed by a slug | `monitor_configs`, `status_page_configs` |
| `<area>_defaults` | the stack-wide baseline object | `monitor_defaults`, `status_page_defaults` |
| `<x>_<y>_mapping` | a relationship, `x -> list(y)` | `monitors_component_mapping`, `rbac_team_mapping` |
| `<area>_definitions` | layer-4 local: config after defaults are resolved | `monitor_definitions`, `status_page_definitions`, `component_definitions` |
| `<x>_ids` | resolved id map handed to a submodule | `label_ids`, `team_ids`, `monitor_ids` |
| `<area>_<child>` | flattened child map, keyed `"<parent>.<child>"` | `status_page_groups["core.platform"]` |
| `*_defaults` local | the slice of a `*_defaults` variable an inner loop needs | `monitor_step_defaults`, `monitor_criteria_defaults` |

Composite map keys use `.` between a parent key and a child key, and `~`
between a key and a sort field (`"gitlab~020~degraded"`). Neither character
appears in a slug, so splitting and prefix-matching stay unambiguous.

Submodule variable types are the one place `any` is acceptable:

```hcl
// modules/<area>/variables.tf
variable "monitor_configs"       { type = any }              // validated by the parent
variable "label_ids"             { type = map(string) }      // derived by the parent
variable "component_definitions" { type = map(object({...})) }
```

Pass-through config is `any` so the type is not maintained in two places; data
the parent *derived* is typed concretely, because that is a contract between
layers rather than user input. Every submodule `variables.tf` opens with a
comment pointing at the parent file that owns the real types.

## 6. Validation

**All validation lives in layer 2** — the parent's `variables-<area>.tf` — and
nowhere else. A submodule assumes its inputs are already correct.

Three rules for a validation block:

1. **Name the offender.** Compute the failing keys in the message rather than
   restating the rule. `terraform` shows one error per variable, so a list is
   worth much more than a sentence:

   ```text
   These monitors probe a destination, so they need `target`
   (or explicit monitor_steps): argocd, trivy.
   ```

2. **Guard the joins.** A key referenced across inputs is validated where it is
   referenced. `monitors_component_mapping` checks its slugs exist in
   `monitor_configs`; `status_page_configs` checks `monitor_key` against
   `monitor_configs` and `monitor_group_key` against `rbac_component_mapping`.
   Cross-variable validation is used deliberately here — without it these fail
   deep inside a submodule as a bare `Invalid index`.

3. **Validate what generation assumes.** Anything layer 4 will silently skip
   must fail at layer 2: a `monitor_type` with no preset catalogue and no
   `monitor_steps`, a `Port` monitor with no `port`, a typo'd preset name.
   A monitor that checks nothing is worse than a plan error.

Where a constraint is the server's, say so in the message
(`"the server caps it at 60000"`).

## 7. Ordering and determinism

Terraform maps are unordered and their keys sort alphabetically, so anything
order-sensitive gets an explicit sort key at layer 4.

* **`order` attributes** fall back to position: `coalesce(group.order, index(keys(page.groups), name) + 1)`. Keys are sorted, so this is stable across plans.
* **Monitor criteria** are first-match-wins server-side, so the preset carries an `order` (offline `10`, extras `50`, operational `90`), the rendered map is keyed `"<monitor>~<order>~<preset>"`, and `sort()` on those keys produces evaluation order. Listing presets in a different order in the stack's config cannot break it.
* **Never** rely on the order of a `for_each` map or on user-supplied key order.

## 8. HCL idioms, and two traps

Reading heterogeneous (`any`) config:

```hcl
try(config.description, null)   // optional attribute -> a value or null
can(config.monitor_steps)       // did the user set this key at all?
```

Never index an `any`-typed config attribute directly — a monitor that omits the
key raises `This object does not have an attribute named …` instead of taking
the default.

Omitting a key entirely, rather than setting it to `[]` or `{}` — the provider
distinguishes them:

```hcl
merge(base, create_incidents ? { incidents = [...] } : {})
```

### Trap 1 — a conditional cannot return two different tuples

`cond ? [a, b, c] : [d]` fails with *Inconsistent conditional result types*:
tuples of different lengths do not unify. This bites whenever a fallback list
is a different length from the primary one. Use `concat()`, which builds a
tuple and needs no unification:

```hcl
criteria = concat(
  [for c in try(step.criteria, []) : merge(local.monitor_criteria_defaults, c)],
  flatten([for _ in range(can(step.criteria) ? 0 : 1) : local.monitor_criteria[key]]),
)
```

`range(cond ? 0 : 1)` is the idiom for "zero or one of these" — it returns
`list(number)`, which always unifies, and it is how
`generated_monitor_steps` emits a step for a generated monitor and nothing for
a hand-written or `Manual` one.

### Trap 2 — `lookup()` on a heterogeneous object

`lookup(obj, key, default)` converts its first argument to a map, which fails
when the object's attribute types differ. Index with `try()` instead:

```hcl
try(local.monitor_type_step_defaults[spec.monitor_type], {})   // not lookup()
```

Flattening one map per parent into one flat map:

```hcl
merge([for key, page in var.status_page_configs : { ... }]...)   // note the ...
```

## 9. Adding an area

1. `variables-<area>.tf` in the parent — types, defaults as `optional(…, x)`, every validation.
2. `modules/<area>/variables.tf` — `any` for pass-through, concrete types for `label_ids` / `team_ids` / `component_definitions`, plus the header comment pointing back.
3. `modules/<area>/locals.tf` — resolve defaults into `<area>_definitions`, flatten children into `"<parent>.<child>"` maps.
4. `modules/<area>/main.tf` — `for_each` over those locals, attributes only.
5. `modules/<area>/README.md` — schema, allowed values, one example per shape.
6. Wire it in the parent `main.tf`, passing `component_definitions`, `label_ids`, `team_ids`, and any ids from another area.
7. `terraform fmt -recursive && terraform validate`.
