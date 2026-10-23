// Monitor statuses and severities are project-level records that already exist
// in every OneUptime project. Resolving them here rather than in the project
// directory is what lets monitor_configs name a severity ("critical") instead
// of threading a data source id through every criterion.
//
// A criterion that needs something outside these sets can still pass a raw id
// through `overrides` - see ./README.md.

data "oneuptime_monitor_status" "operational" {
  name = "Operational"
}

data "oneuptime_monitor_status" "degraded" {
  name = "Degraded"
}

data "oneuptime_monitor_status" "offline" {
  name = "Offline"
}

data "oneuptime_incident_severity" "critical" {
  name = "Critical Incident"
}

data "oneuptime_incident_severity" "major" {
  name = "Major Incident"
}

data "oneuptime_incident_severity" "minor" {
  name = "Minor Incident"
}

data "oneuptime_alert_severity" "high" {
  name = "High"
}

data "oneuptime_alert_severity" "low" {
  name = "Low"
}
