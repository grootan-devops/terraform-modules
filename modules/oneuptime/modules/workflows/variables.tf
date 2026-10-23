// Types and validation live in ../../variables-workflows.tf.

variable "workflow_configs" {
  type        = any
  description = "Workflow configuration, validated by the parent module"
}

variable "workflow_variable_contents" {
  type        = map(string)
  sensitive   = true
  description = "\"<workflow key>.<variable name>\" -> initial variable content"
}

variable "project_id" {
  type        = string
  description = "id of the OneUptime project, substituted for @@project_id@@ in node arguments"
}

variable "monitor_status_ids" {
  type        = map(string)
  description = "monitor status name -> id, substituted for @@monitor_status.<name>@@ in node arguments"
}
