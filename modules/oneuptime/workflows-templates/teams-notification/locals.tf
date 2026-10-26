locals {
  webhook_variable_description = "Microsoft Teams webhook URL. In Teams, open Workflows for the channel, choose \"Send webhook alerts to a channel\", and copy its HTTP POST URL."

  // Every notification this template can build. The five share one shape:
  // a trigger, an optional step that works out the heading, and one Teams
  // message.
  all_notifications = {
    "monitor-status-changed" = {
      name        = "${var.project_name} — Teams — Monitor status changed"
      description = "Posts to Microsoft Teams when a monitor changes status in the ${var.project_name} project: Operational<->Degraded, Operational<->Offline, Degraded->Offline (Offline->Degraded is skipped). Includes previous status."

      nodes = [
        {
          key     = "monitor-status-timeline-on-create-1"
          type    = "monitor-status-timeline-on-create"
          trigger = true

          arguments = {
            select = jsonencode({
              _id             = true
              monitorId       = true
              monitorStatusId = true
              startsAt        = true
              rootCause       = true
              monitor = {
                _id  = true
                name = true
              }
              monitorStatus = {
                _id  = true
                name = true
              }
            })
          }
        },
        {
          key  = "monitor-status-timeline-find-many-1"
          type = "monitor-status-timeline-find-many"

          arguments = {
            limit = "500"
            query = jsonencode({
              monitorId = {
                _type = "ObjectID"
                value = "{{local.components.monitor-status-timeline-on-create-1.returnValues.model.monitorId.value}}"
              }
              startsAt = {
                _type = "LessThan"
                value = "{{local.components.monitor-status-timeline-on-create-1.returnValues.model.startsAt.value}}"
              }
            })
            select = jsonencode({
              _id             = true
              monitorStatusId = true
              startsAt        = true
            })
          }
        },
        {
          key  = "javascript-1"
          type = "javascript"

          arguments = {
            arguments = "{}"
            code      = "var N={'@@monitor_status.operational@@':'Operational','@@monitor_status.degraded@@':'Degraded','@@monitor_status.offline@@':'Offline'};function u(x){if(typeof x==='string'){try{var j=JSON.parse(x);if(j&&typeof j==='object'){x=j;}}catch(e){}}return (x&&typeof x==='object'&&x.value!==undefined)?x.value:x;}var failed=false;var prev=[];try{prev=JSON.parse(`{{local.components.monitor-status-timeline-find-many-1.returnValues.models}}`);}catch(e){failed=true;}if(!Array.isArray(prev)){prev=[];failed=true;}var last=null;for(var i=0;i<prev.length;i++){var p=prev[i];if(p&&p.startsAt&&(!last||new Date(u(p.startsAt))>new Date(u(last.startsAt)))){last=p;}}var from=last?N[u(last.monitorStatusId)]:null;var to=N['{{local.components.monitor-status-timeline-on-create-1.returnValues.model.monitorStatusId.value}}'];var ok={'Operational>Degraded':1,'Degraded>Operational':1,'Operational>Offline':1,'Offline>Operational':1,'Degraded>Offline':1};var notify=false;if(failed){notify=!!to;}else{notify=!!(from&&to&&ok[from+'>'+to]);}var H={'Operational':'🟢 RECOVERED - MONITOR OPERATIONAL','Degraded':'🟡 DEGRADED - MONITOR STATUS CHANGED','Offline':'🔴 OFFLINE - MONITOR DOWN'};return {notify:notify,from:from||'Unknown',to:to||'Unknown',lookupFailed:failed,head:H[to]||'⚪ MONITOR STATUS CHANGED'};"
          }
        },
        {
          key  = "if-else-1"
          type = "if-else"
          next = { yes = "microsoft-teams-send-message-to-channel-1" }

          arguments = {
            "input-1" = "{{local.components.javascript-1.returnValues.returnValue.notify}}"
            "input-2" = "true"
            operator  = "=="
          }
        },
        {
          key  = "microsoft-teams-send-message-to-channel-1"
          type = "microsoft-teams-send-message-to-channel"

          arguments = {
            text = chomp(<<-EOT
              {{local.components.javascript-1.returnValues.returnValue.head}}

              PROJECT: ${var.project_name}
              MONITOR: {{local.components.monitor-status-timeline-on-create-1.returnValues.model.monitor.name}}
              STATUS: {{local.components.javascript-1.returnValues.returnValue.from}} → {{local.components.javascript-1.returnValues.returnValue.to}}
              TIME (UTC): {{local.components.monitor-status-timeline-on-create-1.returnValues.model.startsAt.value}}
              DETAILS: {{local.components.monitor-status-timeline-on-create-1.returnValues.model.rootCause}}

              OPEN IN ONEUPTIME: ${var.dashboard_url}/dashboard/@@project_id@@/monitors/{{local.components.monitor-status-timeline-on-create-1.returnValues.model.monitorId.value}}
              EOT
            )
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          }
        },
      ]

      variables = {
        "teamsWebhookUrl" = {
          description = local.webhook_variable_description
        }
      }
    }

    "alert-state-changed" = {
      name        = "${var.project_name} — Teams — Alert state changed"
      description = "Posts to Microsoft Teams whenever an alert changes state in the ${var.project_name} project."

      nodes = [
        {
          key     = "alert-state-timeline-on-create-1"
          type    = "alert-state-timeline-on-create"
          trigger = true

          arguments = {
            select = jsonencode({
              _id       = true
              createdAt = true
              alertId   = true
              alertState = {
                name = true
              }
              alert = {
                _id                   = true
                title                 = true
                description           = true
                alertNumberWithPrefix = true
                alertSeverity = {
                  name = true
                }
              }
            })
          }
        },
        {
          key  = "javascript-1"
          type = "javascript"

          arguments = {
            code = "var s='{{local.components.alert-state-timeline-on-create-1.returnValues.model.alertState.name}}';var H={'Identified':'🟠 ALERT RAISED','Created':'🟠 ALERT RAISED','Acknowledged':'🟡 ALERT ACKNOWLEDGED','Resolved':'🟢 ALERT RESOLVED'};return {head:H[s]||('⚪ ALERT STATE: '+String(s).toUpperCase())};"
          }
        },
        {
          key  = "microsoft-teams-send-message-to-channel-1"
          type = "microsoft-teams-send-message-to-channel"

          arguments = {
            text = chomp(<<-EOT
              {{local.components.javascript-1.returnValues.returnValue.head}} - {{local.components.alert-state-timeline-on-create-1.returnValues.model.alert.alertNumberWithPrefix}}

              TITLE: {{local.components.alert-state-timeline-on-create-1.returnValues.model.alert.title}}
              NEW STATUS: {{local.components.alert-state-timeline-on-create-1.returnValues.model.alertState.name}}
              PROJECT: ${var.project_name}
              TIME (UTC): {{local.components.alert-state-timeline-on-create-1.returnValues.model.createdAt.value}}
              DESCRIPTION: {{local.components.alert-state-timeline-on-create-1.returnValues.model.alert.description}}

              OPEN IN ONEUPTIME: ${var.dashboard_url}/dashboard/@@project_id@@/alerts/{{local.components.alert-state-timeline-on-create-1.returnValues.model.alert._id}}
              EOT
            )
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          }
        },
      ]

      variables = {
        "teamsWebhookUrl" = {
          description = local.webhook_variable_description
        }
      }
    }

    "incident-state-changed" = {
      name        = "${var.project_name} — Teams — Incident state changed"
      description = "Posts to Microsoft Teams whenever an incident changes state in the ${var.project_name} project."

      nodes = [
        {
          key     = "incident-state-timeline-on-create-1"
          type    = "incident-state-timeline-on-create"
          trigger = true

          arguments = {
            select = jsonencode({
              _id        = true
              createdAt  = true
              incidentId = true
              incidentState = {
                name = true
              }
              incident = {
                _id                      = true
                title                    = true
                description              = true
                incidentNumberWithPrefix = true
                incidentSeverity = {
                  name = true
                }
              }
            })
          }
        },
        {
          key  = "javascript-1"
          type = "javascript"

          arguments = {
            code = "var s='{{local.components.incident-state-timeline-on-create-1.returnValues.model.incidentState.name}}';var H={'Identified':'🔴 INCIDENT IDENTIFIED','Acknowledged':'🟡 INCIDENT ACKNOWLEDGED','Resolved':'🟢 INCIDENT RESOLVED'};return {head:H[s]||('⚪ INCIDENT STATE: '+String(s).toUpperCase())};"
          }
        },
        {
          key  = "microsoft-teams-send-message-to-channel-1"
          type = "microsoft-teams-send-message-to-channel"

          arguments = {
            text = chomp(<<-EOT
              {{local.components.javascript-1.returnValues.returnValue.head}} - {{local.components.incident-state-timeline-on-create-1.returnValues.model.incident.incidentNumberWithPrefix}}

              TITLE: {{local.components.incident-state-timeline-on-create-1.returnValues.model.incident.title}}
              NEW STATUS: {{local.components.incident-state-timeline-on-create-1.returnValues.model.incidentState.name}}
              PROJECT: ${var.project_name}
              TIME (UTC): {{local.components.incident-state-timeline-on-create-1.returnValues.model.createdAt.value}}
              DESCRIPTION: {{local.components.incident-state-timeline-on-create-1.returnValues.model.incident.description}}

              OPEN IN ONEUPTIME: ${var.dashboard_url}/dashboard/@@project_id@@/incidents/{{local.components.incident-state-timeline-on-create-1.returnValues.model.incident._id}}
              EOT
            )
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          }
        },
      ]

      variables = {
        "teamsWebhookUrl" = {
          description = local.webhook_variable_description
        }
      }
    }

    "alert-created" = {
      name        = "${var.project_name} — Teams — Alert created"
      description = "Posts to Microsoft Teams whenever an alert is created in the ${var.project_name} project."

      nodes = [
        {
          key     = "alert-on-create-1"
          type    = "alert-on-create"
          trigger = true

          arguments = {
            select = jsonencode({
              _id                   = true
              title                 = true
              description           = true
              alertNumberWithPrefix = true
              createdAt             = true
              alertSeverity = {
                name = true
              }
              currentAlertState = {
                name = true
              }
            })
          }
        },
        {
          key  = "microsoft-teams-send-message-to-channel-1"
          type = "microsoft-teams-send-message-to-channel"

          arguments = {
            text = chomp(<<-EOT
              🟠 ALERT RAISED - {{local.components.alert-on-create-1.returnValues.model.alertNumberWithPrefix}}

              TITLE: {{local.components.alert-on-create-1.returnValues.model.title}}
              SEVERITY: {{local.components.alert-on-create-1.returnValues.model.alertSeverity.name}}
              STATUS: {{local.components.alert-on-create-1.returnValues.model.currentAlertState.name}}
              PROJECT: ${var.project_name}
              TIME (UTC): {{local.components.alert-on-create-1.returnValues.model.createdAt.value}}
              DESCRIPTION: {{local.components.alert-on-create-1.returnValues.model.description}}

              OPEN IN ONEUPTIME: ${var.dashboard_url}/dashboard/@@project_id@@/alerts/{{local.components.alert-on-create-1.returnValues.model._id}}
              EOT
            )
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          }
        },
      ]

      variables = {
        "teamsWebhookUrl" = {
          description = local.webhook_variable_description
        }
      }
    }

    "incident-created" = {
      name        = "${var.project_name} — Teams — Incident created"
      description = "Posts to Microsoft Teams whenever an incident is created in this project."

      nodes = [
        {
          key     = "incident-on-create-1"
          type    = "incident-on-create"
          trigger = true

          arguments = {
            select = jsonencode({
              _id                      = true
              title                    = true
              description              = true
              incidentNumber           = true
              incidentNumberWithPrefix = true
              createdAt                = true
              incidentSeverity = {
                name = true
              }
              currentIncidentState = {
                name = true
              }
            })
          }
        },
        {
          key  = "teams-1"
          type = "microsoft-teams-send-message-to-channel"
          next = { error = "log-delivery-failed" }

          arguments = {
            text = chomp(<<-EOT
              🔴 INCIDENT OPENED - {{local.components.incident-on-create-1.returnValues.model.incidentNumberWithPrefix}}

              TITLE: {{local.components.incident-on-create-1.returnValues.model.title}}
              SEVERITY: {{local.components.incident-on-create-1.returnValues.model.incidentSeverity.name}}
              STATUS: {{local.components.incident-on-create-1.returnValues.model.currentIncidentState.name}}
              PROJECT: ${var.project_name}
              TIME (UTC): {{local.components.incident-on-create-1.returnValues.model.createdAt.value}}
              DESCRIPTION: {{local.components.incident-on-create-1.returnValues.model.description}}

              OPEN IN ONEUPTIME: ${var.dashboard_url}/dashboard/@@project_id@@/incidents/{{local.components.incident-on-create-1.returnValues.model._id}}
              EOT
            )
            "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
          }
        },
        {
          key  = "log-delivery-failed"
          type = "log"

          arguments = {
            value = "❌ Microsoft Teams could not deliver the incident notification: {{local.components.teams-1.returnValues.error}}"
          }
        },
      ]

      variables = {
        "teamsWebhookUrl" = {
          description = local.webhook_variable_description
        }
      }
    }
  }

  notifications = { for key, workflow in local.all_notifications : key => workflow if contains(var.enabled, key) }
}
