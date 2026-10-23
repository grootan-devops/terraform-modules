terraform {
  required_version = ">= 1.9.0"
  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

// Labels and teams are created by this module (labels.tf, teams.tf) because
// every submodule below needs their ids. Everything else is grouped by the part
// of OneUptime it configures, so a change to on-call never touches monitors.

module "monitors" {
  source = "./modules/monitors"

  application                = var.application
  monitors_component_mapping = var.monitors_component_mapping
  monitor_configs            = var.monitor_configs
  monitor_defaults           = var.monitor_defaults

  component_definitions = local.component_definitions
  label_ids             = local.label_ids
  team_ids              = local.team_ids
}

module "alerts" {
  source = "./modules/alerts"

  alert_grouping_rule_config = var.alert_grouping_rule_config

  component_definitions = local.component_definitions
  label_ids             = local.label_ids
  team_ids              = local.team_ids
}

module "incidents" {
  source = "./modules/incidents"

  incident_grouping_rule_config = var.incident_grouping_rule_config

  component_definitions = local.component_definitions
  label_ids             = local.label_ids
  team_ids              = local.team_ids
}

module "oncall" {
  source = "./modules/oncall"

  on_call_policy_config    = var.on_call_policy_config
  on_call_escalation_rules = var.on_call_escalation_rules

  on_call_schedule_layer_config = var.on_call_schedule_layer_config

  component_definitions = local.component_definitions
  label_ids             = local.label_ids
  team_ids              = local.team_ids
}

// Status pages publish what the monitors submodule creates, so they take its
// ids rather than looking monitors up themselves.
module "status_pages" {
  source = "./modules/status-pages"

  application               = var.application
  status_page_defaults      = var.status_page_defaults
  status_page_configs       = var.status_page_configs
  status_page_announcements = var.status_page_announcements
  monitor_configs           = var.monitor_configs

  component_definitions = local.component_definitions
  label_ids             = local.label_ids
  team_ids              = local.team_ids
  monitor_ids           = module.monitors.monitor_ids
  monitor_group_ids     = module.monitors.monitor_group_ids
}

// Workflows read the ids of what the other areas create: the monitor status
// ids and the project id are substituted into node arguments (see
// modules/workflows/README.md).
module "workflows" {
  source = "./modules/workflows"

  workflow_configs           = var.workflow_configs
  workflow_variable_contents = var.workflow_variable_contents

  project_id         = local.project_id
  monitor_status_ids = module.monitors.monitor_status_ids
}
