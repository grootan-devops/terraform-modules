// Inputs consumed by ./modules/workflows.

variable "workflow_configs" {
  type = map(object({
    name        = string
    description = optional(string)
    is_enabled  = optional(bool, true)

    // The canvas, described as nodes. The module generates the ids, the edges
    // and the layout, so a workflow is only what it does. Listed in flow order:
    // a node with no `next` hands over to the node after it on success.
    nodes = optional(list(object({
      // Names the node. Later nodes refer to it as
      // {{local.components.<key>.returnValues...}}.
      key = string
      // The OneUptime component, e.g. alert-on-create or
      // microsoft-teams-send-message-to-channel.
      type = string
      // The node the workflow starts from. Exactly one per workflow.
      trigger = optional(bool, false)
      // Component arguments, all strings. Structured ones, like a trigger's
      // `select`, are passed through jsonencode(). @@project_id@@ and
      // @@monitor_status.<operational|degraded|offline>@@ are replaced by the
      // project's real ids.
      arguments = optional(map(string), {})
      // output handle -> node key, e.g. { success = "notify", error = "log" }.
      // Replaces the default hand-over to the next node.
      next = optional(map(string))
      // Canvas position. Defaults to one node per row, in list order.
      x = optional(number)
      y = optional(number)
    })), [])

    // Escape hatch: the canvas as raw JSON, instead of nodes. Pass file().
    graph = optional(string)

    // Workflow variables, keyed by variable name. Nodes read them as
    // {{local.variables.<name>}}.
    variables = optional(map(object({
      description = optional(string)
      is_secret   = optional(bool, true)
    })), {})
  }))
  description = "workflow key -> the workflow, its nodes and its variables"
  default     = {}

  validation {
    condition = alltrue([
      for key, wf in var.workflow_configs : (length(wf.nodes) > 0) != (wf.graph != null)
    ])
    error_message = "A workflow needs `nodes` or `graph`, and not both. Check: ${join(", ", sort([for key, wf in var.workflow_configs : key if(length(wf.nodes) > 0) == (wf.graph != null)]))}."
  }

  validation {
    condition     = alltrue([for key, wf in var.workflow_configs : wf.graph == null || can(jsondecode(wf.graph))])
    error_message = "These workflows have a graph that is not valid JSON: ${join(", ", sort([for key, wf in var.workflow_configs : key if wf.graph != null && !can(jsondecode(wf.graph))]))}."
  }

  validation {
    condition = alltrue([
      for key, wf in var.workflow_configs :
      wf.graph == null || (can(jsondecode(wf.graph).nodes) && can(jsondecode(wf.graph).edges))
    ])
    error_message = "These workflows have a graph without `nodes` and `edges`: ${join(", ", sort([for key, wf in var.workflow_configs : key if wf.graph != null && !(can(jsondecode(wf.graph).nodes) && can(jsondecode(wf.graph).edges))]))}."
  }

  validation {
    condition = alltrue([
      for key, wf in var.workflow_configs :
      length(wf.nodes) == 0 || length([for n in wf.nodes : n if n.trigger]) == 1
    ])
    error_message = "A workflow needs exactly one node with `trigger = true`. Check: ${join(", ", sort([for key, wf in var.workflow_configs : key if length(wf.nodes) > 0 && length([for n in wf.nodes : n if n.trigger]) != 1]))}."
  }

  validation {
    condition = alltrue([
      for key, wf in var.workflow_configs :
      length(distinct([for n in wf.nodes : n.key])) == length(wf.nodes)
    ])
    error_message = "These workflows repeat a node key: ${join(", ", sort([for key, wf in var.workflow_configs : key if length(distinct([for n in wf.nodes : n.key])) != length(wf.nodes)]))}."
  }

  validation {
    condition = alltrue(flatten([
      for key, wf in var.workflow_configs : [
        for n in wf.nodes : [
          for handle, target in coalesce(n.next, {}) : contains([for m in wf.nodes : m.key], target)
        ]
      ]
    ]))
    error_message = "These `next` targets are not nodes of their workflow: ${join(", ", sort(flatten([for key, wf in var.workflow_configs : [for n in wf.nodes : [for handle, target in coalesce(n.next, {}) : "${key}.${n.key}.${handle} -> ${target}" if !contains([for m in wf.nodes : m.key], target)]]])))}."
  }
}

variable "workflow_variable_contents" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = <<-EOT
    "<workflow key>.<variable name>" -> the value used when a workflow variable
    is first created. OneUptime never returns the content of a secret variable,
    so it cannot be read back or compared: it is applied on create and ignored
    afterwards. A variable with no entry is created with a placeholder, to be
    replaced in the console.
  EOT

  validation {
    condition = alltrue([
      for ref in keys(var.workflow_variable_contents) :
      contains(flatten([for key, wf in var.workflow_configs : [for name in keys(wf.variables) : "${key}.${name}"]]), ref)
    ])
    // The keys are "<workflow>.<variable>" references, never the secret
    // values, and Terraform refuses to print a message built from a sensitive
    // value, so they are unwrapped to name the offenders.
    error_message = "workflow_variable_contents names variables that are not declared in workflow_configs: ${join(", ", sort([for ref in nonsensitive(keys(var.workflow_variable_contents)) : ref if !contains(flatten([for key, wf in var.workflow_configs : [for name in keys(wf.variables) : "${key}.${name}"]]), ref)]))}."
  }
}
