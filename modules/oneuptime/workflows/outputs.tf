output "workflow_ids" {
  description = "workflow key -> workflow id"
  value       = { for key, workflow in oneuptime_workflow.this : key => workflow.id }
}

output "workflow_variable_ids" {
  description = "\"<workflow key>.<variable name>\" -> workflow variable id"
  value       = { for key, variable in oneuptime_workflow_variable.this : key => variable.id }
}

output "workflow_graphs" {
  description = "workflow key -> the canvas JSON sent to OneUptime"
  value       = { for key, definition in local.workflow_definitions : key => definition.graph }
}
