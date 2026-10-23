locals {
  // Every project gets a label named after itself, so anything this module
  // creates can be found by project in the OneUptime dashboard.
  default_labels_config = {
    "project" = {
      "${var.application}" = "#1100ff"
    }
  }
  project_labels_config = merge(var.labels_config, local.default_labels_config)

  // rbac_component_mapping maps a component to the *list* of groups that own
  // it, so every rule keyed off a component has to resolve that list rather
  // than treat it as a single group. Resolve it once here:
  //
  //   groups      - the owning groups, used to look up a team id
  //   label_names - the component label plus one label per owning group, used
  //                 wherever a rule labels or groups by component
  //
  // Keyed by component, so the submodules keep one resource instance per
  // component instead of fanning out per component/group pair.
  component_definitions = {
    for component, groups in var.rbac_component_mapping : component => {
      groups      = groups
      label_names = distinct(concat([component], groups))
    }
  }

  // Resolved ids handed to the submodules, so a submodule never has to reach
  // back into the labels and teams this module owns.
  label_ids = { for name, label in oneuptime_label.this : name => label.id }
  team_ids  = { for name, team in oneuptime_team.this : name => team.id }
}

locals {
  // Every label belongs to the project the API key is scoped to.
  project_id = values(oneuptime_label.this)[0].project_id
}
