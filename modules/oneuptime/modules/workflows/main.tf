terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

resource "oneuptime_workflow" "this" {
  for_each    = local.workflow_definitions
  name        = each.value.name
  description = each.value.description
  is_enabled  = each.value.is_enabled
  graph       = each.value.graph
}

resource "oneuptime_workflow_variable" "this" {
  for_each    = local.workflow_variables
  workflow_id = oneuptime_workflow.this[each.value.workflow_key].id
  name        = each.value.name
  description = each.value.description
  is_secret   = each.value.is_secret
  content     = each.value.content

  // OneUptime never returns the content of a secret variable, so it reads back
  // as null and could only ever show as a change. It is set on create; rotate
  // it in the console.
  lifecycle {
    ignore_changes = [content]
  }
}
