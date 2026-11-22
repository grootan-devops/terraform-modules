data "oneuptime_monitor_status" "degraded" {
  name = "Degraded"
}

data "oneuptime_monitor_status" "operational" {
  name = "Operational"
}

data "oneuptime_alert_severity" "high" {
  name = "High"
}

locals {
  project_name = title(var.application)

  component_owners = {
    "storefront" = ["frontend", "sre"]
    "checkout"   = ["backend"]
    "data"       = ["dba"]
    "network"    = ["sre"]
    "operations" = ["sre"]
  }

  component_monitors = {
    "storefront" = ["storefront", "storefront-journey", "storefront-tls", "storefront-dns", "storefront-dnssec", "storefront-domain"]
    "checkout"   = ["checkout-api", "checkout-regions", "payment-gateway", "order-export", "checkout-errors"]
    "data"       = ["postgres-primary", "orders-replica-lag", "db-host", "nightly-backup"]
    "network"    = ["edge-gateway", "vpn-concentrator"]
    "operations" = ["backup-report-email", "dc-migration"]
  }

  monitor_configs = {
    "storefront" = {
      display_name            = "Storefront"
      description             = "Home page as customers load it."
      monitor_type            = "Website"
      target                  = "https://www.${var.base_domain}"
      minimum_probe_agreement = 2
      criteria = {
        offline = { remediation_notes = "Check the CDN, then the storefront pods." }
      }
      extra_criteria = [
        {
          name                  = "Rate limited"
          description           = "The CDN rate-limits the probe; the shop itself is up."
          order                 = 5
          filter_condition      = "All"
          filters               = [{ check_on = "Response Status Code", filter_type = "Equal To", value = "429" }]
          change_monitor_status = true
          monitor_status_id     = data.oneuptime_monitor_status.degraded.id
        },
      ]
    }

    "storefront-journey" = {
      display_name        = "Checkout journey"
      description         = "Signs in as the test shopper and reaches the payment form."
      monitor_type        = "Synthetic Monitor"
      monitoring_interval = "*/15 * * * *"
      thresholds          = { execution_time_ms = 20000 }
      step = {
        browser_types        = ["Chromium", "Firefox"]
        screen_size_types    = ["Desktop", "Mobile"]
        retry_count_on_error = 1
        custom_code          = <<-JS
          await page.goto('https://www.${var.base_domain}/login');
          await page.fill('#email', '{{monitorSecrets.test_shopper_email}}');
          await page.fill('#password', '{{monitorSecrets.test_shopper_password}}');
          await page.click('button[type=submit]');
          await page.goto('https://www.${var.base_domain}/checkout');
          await page.waitForSelector('[data-testid=payment-form]');
          return { data: 'payment form reached' };
        JS
      }
    }

    "storefront-tls" = {
      display_name        = "Storefront TLS certificate"
      monitor_type        = "SSL Certificate"
      target              = "https://www.${var.base_domain}"
      monitoring_interval = "0 0 * * *"
      thresholds          = { certificate_expiry_days = 30 }
    }

    "storefront-dns" = {
      display_name        = "Storefront DNS record"
      monitor_type        = "DNS"
      monitoring_interval = "*/15 * * * *"
      criteria_presets    = ["offline", "operational"]
      step = {
        dns_monitor = jsonencode({
          queryName  = "www.${var.base_domain}"
          recordType = "CNAME"
          hostname   = "1.1.1.1"
          port       = 53
          timeout    = 5000
          retries    = 3
        })
      }
    }

    "storefront-dnssec" = {
      display_name        = "Storefront DNSSEC chain"
      monitor_type        = "DNSSEC"
      monitoring_interval = "0 * * * *"
      step = {
        dnssec_monitor = jsonencode({
          domainName = var.base_domain
          resolvers  = ["1.1.1.1", "8.8.8.8"]
        })
      }
    }

    "storefront-domain" = {
      display_name        = "Shop domain registration"
      monitor_type        = "Domain"
      monitoring_interval = "0 0 * * *"
      step = {
        domain_monitor = jsonencode({
          domainName   = var.base_domain
          lookupMethod = "Auto"
          timeout      = 10000
          retries      = 3
        })
      }
    }

    "checkout-api" = {
      display_name = "Checkout API"
      description  = "Deep health check of the checkout service over mTLS."
      monitor_type = "API"
      target       = "https://api.${var.base_domain}/checkout/health"
      step = {
        request_headers        = { "Accept" = "application/json" }
        tls_client_certificate = "{{monitorSecrets.checkout_probe_certificate}}"
        tls_client_key         = "{{monitorSecrets.checkout_probe_key}}"
      }
      criteria = {
        offline = {
          body_contains        = "ok"
          incident_description = "The checkout health check is failing; customers cannot place orders."
          remediation_notes    = "Check the checkout pods, then the payments database and the payment gateway."
        }
        degraded = {
          response_time_ms = 1500
          alert_severity   = "high"
        }
      }
      extra_criteria = [
        {
          name                  = "Read-only"
          description           = "Checkout answers but runs read-only, so orders queue instead of completing."
          order                 = 15
          filter_condition      = "All"
          filters               = [{ check_on = "Response Body", filter_type = "Contains", value = "read-only" }]
          change_monitor_status = true
          monitor_status_id     = data.oneuptime_monitor_status.degraded.id
          create_alerts         = true
          alerts = [
            {
              title              = "Checkout API is read-only"
              description        = "Orders queue until the payments database accepts writes again."
              alert_severity_id  = data.oneuptime_alert_severity.high.id
              auto_resolve_alert = true
              is_private         = false
              remediation_notes  = "Check the payments database failover."
            },
          ]
        },
      ]
    }

    "checkout-regions" = {
      display_name = "Checkout API regions"
      description  = "Checkout health from the EU and US entry points."
      monitor_type = "API"
      monitor_steps = [
        { monitor_destination = "https://eu.api.${var.base_domain}/checkout/health", monitor_destination_type = "URL", request_type = "GET" },
        { monitor_destination = "https://us.api.${var.base_domain}/checkout/health", monitor_destination_type = "URL", request_type = "GET" },
      ]
    }

    "payment-gateway" = {
      display_name        = "Payment gateway"
      description         = "Opens a payment session through the payment gateway."
      monitor_type        = "Custom JavaScript Code"
      monitoring_interval = "*/5 * * * *"
      step = {
        custom_code = <<-JS
          const response = await axios.post(
            'https://payments.${var.base_domain}/v1/sessions',
            { amount: 100, currency: 'EUR', capture: false },
            { headers: { Authorization: 'Bearer {{monitorSecrets.payment_gateway_api_key}}' }, timeout: 5000 }
          );
          return { data: response.status };
        JS
      }
    }

    "order-export" = {
      display_name = "Order export heartbeat"
      description  = "Heartbeat from the ERP order export, every 15 minutes."
      monitor_type = "Incoming Request"
      thresholds   = { heartbeat_timeout_minutes = 30 }
      criteria = {
        offline = {
          incident_severity = "major"
          remediation_notes = "Check the order-export CronJob in the checkout namespace."
          overrides = {
            incident_grouping = jsonencode({
              groupByJSONPath      = "$.warehouse"
              resolvedWhenJSONPath = "$.status"
              resolvedWhenValue    = "ok"
            })
          }
        }
      }
    }

    "checkout-errors" = {
      display_name        = "Checkout error logs"
      description         = "Error and fatal logs from the checkout service."
      monitor_type        = "Logs"
      monitoring_interval = "*/5 * * * *"
      monitor_steps = [
        {
          log_monitor = jsonencode({
            attributes          = { "k8s.namespace.name" = "checkout" }
            body                = ""
            severityTexts       = ["Error", "Fatal"]
            telemetryServiceIds = []
            lastXSecondsOfLogs  = 300
          })
          criteria = [
            {
              name                  = "Error spike"
              description           = "More than 50 error logs from checkout in five minutes."
              filter_condition      = "All"
              filters               = [{ check_on = "Log Count", filter_type = "Greater Than", value = "50" }]
              change_monitor_status = true
              monitor_status_id     = data.oneuptime_monitor_status.degraded.id
              create_alerts         = true
              alerts = [
                {
                  title              = "Checkout error logs are spiking"
                  description        = "Checkout logged more than 50 errors in five minutes."
                  alert_severity_id  = data.oneuptime_alert_severity.high.id
                  auto_resolve_alert = true
                  is_private         = false
                },
              ]
            },
            {
              name                  = "Operational"
              description           = "Checkout error logs are within the normal range."
              filter_condition      = "All"
              filters               = [{ check_on = "Log Count", filter_type = "Less Than Or Equal To", value = "50" }]
              change_monitor_status = true
              monitor_status_id     = data.oneuptime_monitor_status.operational.id
            },
          ]
        },
      ]
    }

    "postgres-primary" = {
      display_name = "PostgreSQL primary"
      monitor_type = "Port"
      target       = "postgres.internal.${var.base_domain}"
      port         = 5432
    }

    "orders-replica-lag" = {
      display_name        = "Orders replica lag"
      description         = "Replication lag of the orders read replica."
      monitor_type        = "SQL Query"
      monitoring_interval = "*/5 * * * *"
      thresholds          = { query_time_ms = 2000 }
      step = {
        sql_monitor = jsonencode({
          databaseType = "PostgreSQL"
          host         = "postgres-replica.internal.${var.base_domain}"
          port         = 5432
          databaseName = "orders"
          username     = "oneuptime_probe"
          password     = "{{monitorSecrets.orders_probe_password}}"
          query        = "SELECT COALESCE(EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()), 0)::int"
        })
      }
      extra_criteria = [
        {
          name                  = "Replica lagging"
          description           = "The orders replica is more than 60 seconds behind the primary."
          filter_condition      = "All"
          filters               = [{ check_on = "SQL Query Scalar Value", filter_type = "Greater Than", value = "60" }]
          change_monitor_status = true
          monitor_status_id     = data.oneuptime_monitor_status.degraded.id
          create_alerts         = true
          alerts = [
            {
              title              = "Orders replica is lagging"
              description        = "Order history may be stale for customers."
              alert_severity_id  = data.oneuptime_alert_severity.high.id
              auto_resolve_alert = true
              is_private         = false
            },
          ]
        },
      ]
    }

    "db-host" = {
      display_name = "Orders database host"
      description  = "Agent-reported metrics of the database server."
      monitor_type = "Server"
      thresholds   = { disk_path = "/var/lib/postgresql", disk_percent = 80 }
    }

    "nightly-backup" = {
      display_name = "Nightly backup heartbeat"
      description  = "Heartbeat from the nightly database backup job."
      monitor_type = "Incoming Request"
      thresholds   = { heartbeat_timeout_minutes = 1500 }
      criteria = {
        offline = {
          incident_severity = "major"
          remediation_notes = "Check the backup CronJob in the data namespace."
        }
      }
    }

    "edge-gateway" = {
      display_name = "Edge gateway"
      monitor_type = "Ping"
      target       = "203.0.113.10"
      target_type  = "IP"
      thresholds   = { packet_loss_percent = 5 }
    }

    "vpn-concentrator" = {
      display_name = "VPN concentrator"
      monitor_type = "IP"
      target       = "198.51.100.20"
    }

    "backup-report-email" = {
      display_name = "Backup report mailbox"
      description  = "Daily report email from the backup appliance."
      monitor_type = "Incoming Email"
      thresholds   = { heartbeat_timeout_minutes = 1500 }
      criteria = {
        offline = { incident_severity = "minor" }
      }
    }

    "dc-migration" = {
      display_name = "Datacenter migration"
      description  = "Set by hand during the migration window."
      monitor_type = "Manual"
    }
  }

  status_pages = {
    "public" = {
      name                                = "${local.project_name} Status"
      description                         = "Customer-facing status of the shop."
      label_names                         = ["storefront", var.application]
      page_title                          = "${local.project_name} Status"
      page_description                    = "Live availability of the shop, checkout and payments."
      show_subscriber_page_on_status_page = true
      enable_email_subscribers            = true

      groups = {
        "shop"     = { name = "Shop" }
        "checkout" = { name = "Checkout" }
        "payments" = { name = "Payments" }
      }

      monitor_rules = {
        "shop"     = { group_key = "shop", label_names = ["storefront"] }
        "payments" = { group_key = "payments", monitor_name_pattern = "^Payment gateway$" }
      }

      resources = {
        "checkout-api" = {
          monitor_key         = "checkout-api"
          group_key           = "checkout"
          display_name        = "Checkout"
          display_description = "Basket, checkout and order placement."
        }
      }

      header_links = {
        "help" = { title = "Help centre", link = "https://help.${var.base_domain}" }
      }

      footer_links = {
        "privacy" = { title = "Privacy", link = "https://www.${var.base_domain}/privacy", order = 1 }
        "terms"   = { title = "Terms", link = "https://www.${var.base_domain}/terms", order = 2 }
      }

      domain = { domain_name = var.base_domain, subdomain = "status" }

      subscribers = {
        "customer-care" = {
          subscriber_email = "customer-care@example.com"
          internal_note    = "Customer care hears about every public incident."
        }
      }

      owner_group_names = ["sre", "backend"]
    }

    "internal" = {
      name                                = "${local.project_name} Internal Status"
      description                         = "Every monitor of the shop, for engineers and support."
      label_names                         = ["operations", var.application]
      is_public_status_page               = false
      enable_search_engine_indexing       = false
      ip_whitelist                        = join("\n", var.internal_status_page_cidrs)
      show_incident_labels_on_status_page = true
      show_episode_labels_on_status_page  = true
      show_subscriber_page_on_status_page = true
      enable_email_subscribers            = true
      enable_microsoft_teams_subscribers  = true

      groups = {
        "storefront"     = { name = "Storefront" }
        "checkout"       = { name = "Checkout" }
        "data"           = { name = "Data" }
        "infrastructure" = { name = "Infrastructure", is_expanded_by_default = false }
      }

      monitor_rules = {
        "storefront" = { group_key = "storefront", label_names = ["storefront"] }
        "checkout"   = { group_key = "checkout", label_names = ["checkout"] }
        "data"       = { group_key = "data", label_names = ["data"] }
        "network"    = { group_key = "infrastructure", label_names = ["network"] }
        "operations" = { group_key = "infrastructure", label_names = ["operations"] }
      }

      header_links = {
        "runbooks" = { title = "Runbooks", link = "https://runbooks.${var.base_domain}/${var.application}" }
      }

      footer_links = {
        "oneuptime" = { title = "Open in OneUptime", link = "${var.oneuptime_url}/dashboard" }
      }

      private_users = {
        "support-lead"       = { email = "support-lead@example.com" }
        "incident-commander" = { email = "incident-commander@example.com" }
      }

      subscribers = {
        "sre-mail" = { subscriber_email = "sre@example.com" }
        "sre-teams" = {
          microsoft_teams_workspace_name       = local.project_name
          microsoft_teams_incoming_webhook_url = var.status_page_teams_webhook_url
        }
      }

      owner_group_names = ["dba"]
      owner_user_ids    = var.status_page_owner_user_ids
    }
  }

  status_page_announcements = {
    "checkout-maintenance" = {
      title                = "Planned checkout maintenance"
      description          = "Checkout may be unavailable for up to 15 minutes while the payments database is upgraded."
      show_announcement_at = "2026-12-06T01:00:00Z"
      end_announcement_at  = "2026-12-06T02:00:00Z"
      monitor_keys         = ["checkout-api"]
    }

    "internal-page-live" = {
      title                                      = "Internal status page is live"
      description                                = "Subscribe from this page to hear about every incident by email or in Teams."
      show_announcement_at                       = "2026-12-01T09:00:00Z"
      status_page_keys                           = ["internal"]
      should_status_page_subscribers_be_notified = false
    }
  }

  workflow_configs = {
    "major-incident-bridge" = {
      name        = "${local.project_name} — Teams — Major incident bridge"
      description = "Opens the major incident bridge in Teams for every critical incident."

      nodes = [
        {
          key     = "incident-on-create-1"
          type    = "incident-on-create"
          trigger = true
          arguments = {
            select = jsonencode({
              _id                      = true
              title                    = true
              incidentNumberWithPrefix = true
              incidentSeverity         = { name = true }
            })
          }
        },
        {
          key  = "if-critical"
          type = "if-else"
          next = { yes = "teams-bridge", no = "log-not-critical" }
          arguments = {
            "input-1" = "{{local.components.incident-on-create-1.returnValues.model.incidentSeverity.name}}"
            "input-2" = "Critical Incident"
            operator  = "=="
          }
        },
        {
          key  = "teams-bridge"
          type = "microsoft-teams-send-message-to-channel"
          next = { error = "log-delivery-failed" }
          arguments = {
            text          = "MAJOR INCIDENT {{local.components.incident-on-create-1.returnValues.model.incidentNumberWithPrefix}}: {{local.components.incident-on-create-1.returnValues.model.title}}. Join the bridge: ${var.oneuptime_url}/dashboard/@@project_id@@/incidents/{{local.components.incident-on-create-1.returnValues.model._id}}"
            "webhook-url" = "{{local.variables.majorIncidentWebhookUrl}}"
          }
        },
        {
          key  = "log-not-critical"
          type = "log"
          next = {}
          x    = 450
          y    = 600
          arguments = {
            value = "Not a major incident: {{local.components.incident-on-create-1.returnValues.model.incidentSeverity.name}}"
          }
        },
        {
          key  = "log-delivery-failed"
          type = "log"
          arguments = {
            value = "Teams could not deliver the major incident message: {{local.components.teams-bridge.returnValues.error}}"
          }
        },
      ]

      variables = {
        "majorIncidentWebhookUrl" = { description = "Teams webhook of the major incident channel." }
      }
    }

    "monitor-offline-audit" = {
      name        = "${local.project_name} — Log — Monitor offline"
      description = "Logs every monitor that goes offline with its dashboard link and runbook."

      nodes = [
        {
          key     = "status-changed"
          type    = "monitor-status-timeline-on-create"
          trigger = true
          arguments = {
            select = jsonencode({
              _id             = true
              monitorId       = true
              monitorStatusId = true
              monitor         = { name = true }
            })
          }
        },
        {
          key  = "is-offline"
          type = "if-else"
          next = { yes = "log-offline" }
          arguments = {
            "input-1" = "{{local.components.status-changed.returnValues.model.monitorStatusId.value}}"
            "input-2" = "@@monitor_status.offline@@"
            operator  = "=="
          }
        },
        {
          key  = "log-offline"
          type = "log"
          arguments = {
            value = "{{local.components.status-changed.returnValues.model.monitor.name}} is offline. Dashboard: ${var.oneuptime_url}/dashboard/@@project_id@@/monitors/{{local.components.status-changed.returnValues.model.monitorId.value}} Runbook: {{local.variables.runbookUrl}}"
          }
        },
      ]

      variables = {
        "runbookUrl" = { description = "Base URL of the shop runbooks.", is_secret = false }
      }
    }

    "incident-state-audit" = {
      name        = "${local.project_name} — Log — Incident state changed"
      description = "Built in the console and adopted as a raw canvas; enable once the audit sink is ready."
      is_enabled  = false
      graph = jsonencode({
        nodes = [
          {
            id       = uuidv5("dns", "incident-state-audit/state-changed")
            type     = "node"
            width    = 256
            height   = 175
            position = { x = 100, y = 100 }
            data = {
              id            = "state-changed"
              nodeType      = "Node"
              componentType = "Trigger"
              metadataId    = "incident-state-timeline-on-create"
              internalId    = uuidv5("dns", "incident-state-audit/state-changed/internal")
              arguments = {
                select = jsonencode({ _id = true, incidentId = true, incidentState = { name = true } })
              }
            }
          },
          {
            id       = uuidv5("dns", "incident-state-audit/log-state")
            type     = "node"
            width    = 256
            height   = 175
            position = { x = 100, y = 350 }
            data = {
              id            = "log-state"
              nodeType      = "Node"
              componentType = "Component"
              metadataId    = "log"
              internalId    = uuidv5("dns", "incident-state-audit/log-state/internal")
              arguments = {
                value = "Incident {{local.components.state-changed.returnValues.model.incidentId.value}} is now {{local.components.state-changed.returnValues.model.incidentState.name}}"
              }
            }
          },
        ]
        edges = [
          {
            id           = uuidv5("dns", "incident-state-audit/state-changed.success->log-state")
            source       = uuidv5("dns", "incident-state-audit/state-changed")
            target       = uuidv5("dns", "incident-state-audit/log-state")
            sourceHandle = "success"
            targetHandle = "in"
            animated     = false
          },
        ]
      })
    }
  }
}

module "teams_notifications" {
  source = "../../../modules/oneuptime/workflows-templates/teams-notification"

  project_name      = local.project_name
  dashboard_url     = var.oneuptime_url
  teams_webhook_url = var.teams_webhook_url
}

module "oneuptime" {
  source = "../../../modules/oneuptime"

  application = var.application

  labels_config = {
    "component" = {
      "storefront" = "#F52750"
      "checkout"   = "#1F6FEB"
      "data"       = "#614C3F"
      "network"    = "#CED431"
      "operations" = "#8250DF"
    }
    "group" = {
      "frontend" = "#FB8500"
      "backend"  = "#2DA44E"
      "sre"      = "#0969DA"
      "dba"      = "#6E7781"
    }
  }

  rbac_component_mapping = local.component_owners

  rbac_team_mapping = {
    "frontend" = ["frontend@example.com"]
    "backend"  = ["backend@example.com"]
    "sre"      = ["sre@example.com"]
    "dba"      = ["dba@example.com"]
  }

  monitors_component_mapping = local.component_monitors
  monitor_configs            = local.monitor_configs

  monitor_defaults = {
    monitor_step = {
      request_headers = { "User-Agent" = "OneUptime-Probe/${var.application}" }
    }
    thresholds = { response_time_ms = 3000 }
  }

  on_call_overrides = {
    "checkout" = {
      escalate_after_in_minutes                        = 5
      repeat_policy_if_no_one_acknowledges_no_of_times = 5
      schedule_enabled                                 = true
    }
    "data" = { schedule_enabled = true }
  }

  on_call_schedule_layer_config = {
    starts_at     = "2026-01-05T09:00:00.000Z"
    hand_off_time = "2026-01-05T09:00:00.000Z"
    rotation      = { interval_type = "Week", interval_count = 1 }
  }

  status_page_defaults = {
    overall_uptime_percent_precision = "99% (Two Decimal)"
    group                            = { uptime_percent_precision = "99% (Two Decimal)" }
    resource                         = { uptime_percent_precision = "99% (Two Decimal)" }
  }

  status_page_configs       = local.status_pages
  status_page_announcements = local.status_page_announcements

  workflow_configs = merge(module.teams_notifications.workflow_configs, local.workflow_configs)
  workflow_variable_contents = merge(module.teams_notifications.workflow_variable_contents, {
    "major-incident-bridge.majorIncidentWebhookUrl" = var.major_incident_webhook_url
    "monitor-offline-audit.runbookUrl"              = "https://runbooks.${var.base_domain}/${var.application}"
  })
}
