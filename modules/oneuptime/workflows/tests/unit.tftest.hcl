// Unit tests for workflows/, called directly with the normalized inputs
// the parent module (modules/oneuptime) would pass it. No OneUptime instance or
// API key: the mock provider answers every call, so `command = apply` only
// builds state in memory.
mock_provider "oneuptime" {}

variables {
  // From the parent: the project id and the monitors submodule's status ids.
  project_id = "project-1234"

  monitor_status_ids = {
    operational = "status-operational"
    degraded    = "status-degraded"
    offline     = "status-offline"
  }

  // workflow_configs after the parent's optional() defaults
  // (modules/oneuptime/variables-workflows.tf): every node attribute present,
  // `arguments` and `next` typed as map(string).
  workflow_configs = {
    // Linear: no node sets `next`.
    "alert-created" = {
      name        = "Core - Teams - Alert created"
      description = "Posts to Microsoft Teams whenever an alert is created."
      is_enabled  = true
      graph       = null
      nodes = [
        {
          key       = "alert-on-create-1"
          type      = "alert-on-create"
          trigger   = true
          arguments = tomap({ select = "{\"_id\":true,\"title\":true}" })
          next      = null
          x         = null
          y         = null
        },
        {
          key     = "teams-1"
          type    = "microsoft-teams-send-message-to-channel"
          trigger = false
          arguments = tomap({
            text          = "ALERT: {{local.components.alert-on-create-1.returnValues.model.title}} https://oneuptime.example.com/dashboard/@@project_id@@/alerts"
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          })
          next = null
          x    = null
          y    = null
        },
      ]
      variables = {
        "teamsWebhookUrl" = { description = "Teams webhook URL", is_secret = true }
        "channelName"     = { description = "Channel named in the message", is_secret = false }
      }
    }

    // Branching: an if-else with yes/no, a node that ends the flow with
    // next = {}, and one with an explicit canvas position.
    "monitor-status" = {
      name        = "Core - Monitor status"
      description = null
      is_enabled  = false
      graph       = null
      nodes = [
        {
          key       = "status-changed"
          type      = "monitor-status-timeline-on-create"
          trigger   = true
          arguments = tomap({})
          next      = null
          x         = null
          y         = null
        },
        {
          key     = "is-offline"
          type    = "if-else"
          trigger = false
          arguments = tomap({
            "input-1" = "{{local.components.status-changed.returnValues.model.monitorStatusId.value}}"
            "input-2" = "@@monitor_status.offline@@"
            operator  = "=="
          })
          next = tomap({ yes = "notify", no = "log" })
          x    = null
          y    = null
        },
        {
          key       = "notify"
          type      = "javascript"
          trigger   = false
          arguments = tomap({ code = "var s={'@@monitor_status.operational@@':'up','@@monitor_status.degraded@@':'slow','@@monitor_status.offline@@':'down'};" })
          next      = tomap({})
          x         = 400
          y         = 375
        },
        {
          key       = "log"
          type      = "log"
          trigger   = false
          arguments = tomap({})
          next      = null
          x         = null
          y         = null
        },
      ]
      variables = {}
    }

    // Escape hatch: a raw canvas, formatted the way a console export is.
    "imported" = {
      name        = "Core - Imported"
      description = "Built in the console"
      is_enabled  = true
      graph       = "{\n  \"nodes\": [ { \"id\": \"a\" } ],\n  \"edges\": []\n}\n"
      nodes       = []
      variables   = {}
    }
  }

  workflow_variable_contents = {
    "alert-created.teamsWebhookUrl" = "https://example.com/webhook"
  }
}

run "one_workflow_per_config_with_its_attributes" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_workflow.this)) == toset(["alert-created", "monitor-status", "imported"])
    error_message = "Expected one workflow per workflow_configs entry."
  }

  assert {
    condition = (
      oneuptime_workflow.this["alert-created"].name == "Core - Teams - Alert created"
      && oneuptime_workflow.this["alert-created"].description == "Posts to Microsoft Teams whenever an alert is created."
      && oneuptime_workflow.this["alert-created"].is_enabled == true
      && oneuptime_workflow.this["monitor-status"].is_enabled == false
    )
    error_message = "name, description and is_enabled should pass straight through."
  }
}

run "nodes_are_rendered_onto_the_canvas" {
  command = plan

  assert {
    condition     = length(jsondecode(oneuptime_workflow.this["alert-created"].graph).nodes) == 2
    error_message = "Every node should be on the canvas."
  }

  assert {
    condition = { for node in jsondecode(oneuptime_workflow.this["alert-created"].graph).nodes : node.data.id => node }["alert-on-create-1"] == {
      id       = uuidv5("dns", "alert-created/alert-on-create-1")
      type     = "node"
      width    = 256
      height   = 175
      position = { x = 100, y = 100 }
      data = {
        id            = "alert-on-create-1"
        nodeType      = "Node"
        componentType = "Trigger"
        metadataId    = "alert-on-create"
        internalId    = uuidv5("dns", "alert-created/alert-on-create-1/internal")
        arguments     = { select = "{\"_id\":true,\"title\":true}" }
      }
    }
    error_message = "The trigger node should be a Trigger with a uuidv5 id and internalId, its type as metadataId, in the first row."
  }

  assert {
    condition = (
      { for node in jsondecode(oneuptime_workflow.this["alert-created"].graph).nodes : node.data.id => node }["teams-1"].data.componentType == "Component"
      && { for node in jsondecode(oneuptime_workflow.this["alert-created"].graph).nodes : node.data.id => node }["teams-1"].position == { x = 100, y = 350 }
    )
    error_message = "A non-trigger node should be a Component, one row (250) below the node before it."
  }

  assert {
    condition = (
      { for node in jsondecode(oneuptime_workflow.this["monitor-status"].graph).nodes : node.data.id => node.position }["notify"] == { x = 400, y = 375 }
      && { for node in jsondecode(oneuptime_workflow.this["monitor-status"].graph).nodes : node.data.id => node.position }["log"] == { x = 100, y = 850 }
    )
    error_message = "A node's own x/y should win; otherwise it sits in the row of its list position."
  }

  assert {
    condition = length(distinct(flatten([
      for workflow in oneuptime_workflow.this : [for node in jsondecode(workflow.graph).nodes : node.id]
    ]))) == 7
    error_message = "Node ids should be unique across workflows."
  }
}

run "a_node_without_next_hands_over_on_success" {
  command = plan

  assert {
    condition = jsondecode(oneuptime_workflow.this["alert-created"].graph).edges == [
      {
        id           = uuidv5("dns", "alert-created/alert-on-create-1.success->teams-1")
        source       = uuidv5("dns", "alert-created/alert-on-create-1")
        target       = uuidv5("dns", "alert-created/teams-1")
        sourceHandle = "success"
        targetHandle = "in"
        animated     = false
      },
    ]
    error_message = "A linear workflow should get one success edge from each node to the next, and none from the last."
  }
}

run "next_replaces_the_default_hand_over" {
  command = plan

  assert {
    condition = [
      for edge in jsondecode(oneuptime_workflow.this["monitor-status"].graph).edges : [edge.source, edge.sourceHandle, edge.target]
      ] == [
      [uuidv5("dns", "monitor-status/is-offline"), "no", uuidv5("dns", "monitor-status/log")],
      [uuidv5("dns", "monitor-status/is-offline"), "yes", uuidv5("dns", "monitor-status/notify")],
      [uuidv5("dns", "monitor-status/status-changed"), "success", uuidv5("dns", "monitor-status/is-offline")],
    ]
    error_message = "Branches should follow `next`, a node with next = {} should end the flow, and edges should be sorted."
  }

  assert {
    condition = (
      jsondecode(oneuptime_workflow.this["monitor-status"].graph).edges[1].id == uuidv5("dns", "monitor-status/is-offline.yes->notify")
      && alltrue([for edge in jsondecode(oneuptime_workflow.this["monitor-status"].graph).edges : edge.targetHandle == "in" && edge.animated == false])
    )
    error_message = "Edge ids should be stable uuidv5s of source, handle and target, entering on the `in` handle."
  }
}

run "project_and_monitor_status_tokens_are_substituted" {
  command = plan

  assert {
    condition     = { for node in jsondecode(oneuptime_workflow.this["alert-created"].graph).nodes : node.data.id => node.data.arguments }["teams-1"].text == "ALERT: {{local.components.alert-on-create-1.returnValues.model.title}} https://oneuptime.example.com/dashboard/project-1234/alerts"
    error_message = "@@project_id@@ should be replaced with the project id, leaving {{...}} references alone."
  }

  assert {
    condition     = { for node in jsondecode(oneuptime_workflow.this["monitor-status"].graph).nodes : node.data.id => node.data.arguments }["is-offline"]["input-2"] == "status-offline"
    error_message = "@@monitor_status.offline@@ should be replaced with the offline status id."
  }

  assert {
    condition     = { for node in jsondecode(oneuptime_workflow.this["monitor-status"].graph).nodes : node.data.id => node.data.arguments }["notify"].code == "var s={'status-operational':'up','status-degraded':'slow','status-offline':'down'};"
    error_message = "Every monitor status token in one argument should be replaced."
  }
}

run "a_raw_graph_is_passed_through_re_encoded" {
  command = plan

  assert {
    condition     = oneuptime_workflow.this["imported"].graph == "{\"edges\":[],\"nodes\":[{\"id\":\"a\"}]}"
    error_message = "A raw graph should be sent as its canonical JSON, so formatting never shows as a change."
  }
}

run "variables_take_their_content_or_a_placeholder" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_workflow_variable.this)) == toset(["alert-created.teamsWebhookUrl", "alert-created.channelName"])
    error_message = "Workflow variables should be keyed \"<workflow>.<variable>\"."
  }

  assert {
    condition = (
      oneuptime_workflow_variable.this["alert-created.teamsWebhookUrl"].name == "teamsWebhookUrl"
      && oneuptime_workflow_variable.this["alert-created.teamsWebhookUrl"].description == "Teams webhook URL"
      && oneuptime_workflow_variable.this["alert-created.teamsWebhookUrl"].is_secret == true
      && oneuptime_workflow_variable.this["alert-created.channelName"].is_secret == false
    )
    error_message = "A variable should keep its name, description and is_secret."
  }

  assert {
    condition     = nonsensitive(oneuptime_workflow_variable.this["alert-created.teamsWebhookUrl"].content == "https://example.com/webhook")
    error_message = "A variable listed in workflow_variable_contents should be created with that content."
  }

  assert {
    condition     = nonsensitive(oneuptime_workflow_variable.this["alert-created.channelName"].content == "PLACEHOLDER - set the real value in the OneUptime console")
    error_message = "A variable with no entry in workflow_variable_contents should be created with the placeholder."
  }
}

run "outputs_and_variables_point_at_their_workflow" {
  command = apply

  assert {
    condition = alltrue([
      for key, variable in oneuptime_workflow_variable.this :
      variable.workflow_id == oneuptime_workflow.this["alert-created"].id
    ])
    error_message = "Each variable should belong to its own workflow."
  }

  assert {
    condition     = output.workflow_ids == { for key, workflow in oneuptime_workflow.this : key => workflow.id }
    error_message = "workflow_ids should map every workflow key to its id."
  }

  assert {
    condition     = output.workflow_variable_ids == { for key, variable in oneuptime_workflow_variable.this : key => variable.id }
    error_message = "workflow_variable_ids should map every \"<workflow>.<variable>\" key to its id."
  }

  assert {
    condition     = output.workflow_graphs == { for key, workflow in oneuptime_workflow.this : key => workflow.graph }
    error_message = "workflow_graphs should be the exact canvas JSON sent to OneUptime."
  }
}
