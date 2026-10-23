locals {
  // A new variable needs some content; the real value is set in the console
  // (or supplied through workflow_variable_contents).
  placeholder_content = "PLACEHOLDER - set the real value in the OneUptime console"

  // Ids a node argument can name instead of hard-coding them, so the same
  // workflow works in every project.
  argument_tokens = {
    "@@project_id@@"                 = var.project_id
    "@@monitor_status.operational@@" = var.monitor_status_ids["operational"]
    "@@monitor_status.degraded@@"    = var.monitor_status_ids["degraded"]
    "@@monitor_status.offline@@"     = var.monitor_status_ids["offline"]
  }

  // Nodes are laid out one per row. Positions are a convenience for the canvas;
  // the workflow runs the same wherever a node sits.
  node_row_height = 250

  // "<workflow>.<node>" -> the node as the canvas stores it.
  workflow_nodes = merge([
    for key, wf in var.workflow_configs : {
      for index, node in wf.nodes : "${key}.${node.key}" => {
        workflow_key = key
        key          = node.key
        index        = index
        node = {
          id       = uuidv5("dns", "${key}/${node.key}")
          type     = "node"
          width    = 256
          height   = 175
          position = { x = coalesce(node.x, 100), y = coalesce(node.y, 100 + index * local.node_row_height) }
          data = {
            id            = node.key
            nodeType      = "Node"
            componentType = node.trigger ? "Trigger" : "Component"
            metadataId    = node.type
            internalId    = uuidv5("dns", "${key}/${node.key}/internal")
            arguments = {
              for name, value in node.arguments : name => replace(
                replace(
                  replace(
                    replace(
                      value,
                      "@@project_id@@", local.argument_tokens["@@project_id@@"]
                    ),
                    "@@monitor_status.operational@@", local.argument_tokens["@@monitor_status.operational@@"]
                  ),
                  "@@monitor_status.degraded@@", local.argument_tokens["@@monitor_status.degraded@@"]
                ),
                "@@monitor_status.offline@@", local.argument_tokens["@@monitor_status.offline@@"]
              )
            }
          }
        }
      }
    }
  ]...)

  // "<workflow>.<source>.<handle>" -> one edge. A node with no `next` hands
  // over to the node listed after it, on success.
  workflow_edges = merge([
    for key, wf in var.workflow_configs : merge([
      for index, node in wf.nodes : {
        for handle, target in(
          node.next != null ? node.next : {
            for _ in range(index + 1 < length(wf.nodes) ? 1 : 0) : "success" => wf.nodes[index + 1].key
          }
          ) : "${key}.${node.key}.${handle}" => {
          workflow_key = key
          id           = uuidv5("dns", "${key}/${node.key}.${handle}->${target}")
          source       = uuidv5("dns", "${key}/${node.key}")
          target       = uuidv5("dns", "${key}/${target}")
          sourceHandle = handle
          targetHandle = "in"
          animated     = false
        }
      }
    ]...)
  ]...)

  workflow_definitions = {
    for key, wf in var.workflow_configs : key => {
      name        = wf.name
      description = wf.description
      is_enabled  = wf.is_enabled
      // Re-encoded so formatting in a raw graph never shows up as a change.
      graph = wf.graph != null ? jsonencode(jsondecode(wf.graph)) : jsonencode({
        nodes = [for node in local.workflow_nodes : node.node if node.workflow_key == key]
        edges = [
          for edge_key in sort([for k, e in local.workflow_edges : k if e.workflow_key == key]) : {
            for attr, value in local.workflow_edges[edge_key] : attr => value if attr != "workflow_key"
          }
        ]
      })
    }
  }

  // Flattened to "<workflow>.<variable>".
  workflow_variables = merge([
    for key, wf in var.workflow_configs : {
      for name, variable in wf.variables : "${key}.${name}" => {
        workflow_key = key
        name         = name
        description  = variable.description
        is_secret    = variable.is_secret
        content      = lookup(var.workflow_variable_contents, "${key}.${name}", local.placeholder_content)
      }
    }
  ]...)
}
