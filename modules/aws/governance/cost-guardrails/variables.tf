variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "notifications" {
  description = "Subscribers for budget and anomaly alerts."
  type = object({
    sns = optional(object({
      enabled   = optional(bool, false)
      topic_arn = optional(string)
    }), {})
    emails = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.notifications.sns.enabled || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", var.notifications.sns.topic_arn))
    error_message = "notifications.sns.topic_arn: an SNS topic ARN."
  }

  validation {
    condition     = length(var.notifications.emails) <= 10 && alltrue([for e in var.notifications.emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "notifications.emails: up to 10 email addresses."
  }

  validation {
    condition     = (length(var.budgets) == 0 && !var.anomaly_detection.enabled) || var.notifications.sns.enabled || length(var.notifications.emails) > 0
    error_message = "notifications: SNS or emails required."
  }
}

variable "budgets" {
  description = "Budgets by key."
  type = map(object({
    amount    = optional(number)
    unit      = optional(string, "USD")
    time_unit = optional(string, "MONTHLY")
    type      = optional(string, "COST")
    metric    = optional(string, "UnblendedCost")
    filter = optional(object({
      tags            = optional(map(list(string)), {})
      services        = optional(list(string), [])
      linked_accounts = optional(list(string), [])
    }), {})
    notifications = optional(list(object({
      type                = string
      threshold           = number
      threshold_type      = optional(string, "PERCENTAGE")
      comparison_operator = optional(string, "GREATER_THAN")
      })), [
      { type = "ACTUAL", threshold = 80, threshold_type = "PERCENTAGE", comparison_operator = "GREATER_THAN" },
      { type = "ACTUAL", threshold = 100, threshold_type = "PERCENTAGE", comparison_operator = "GREATER_THAN" },
      { type = "FORECASTED", threshold = 100, threshold_type = "PERCENTAGE", comparison_operator = "GREATER_THAN" },
    ])
    auto_adjust = optional(object({
      enabled          = optional(bool, false)
      lookback_periods = optional(number)
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.budgets) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "budgets keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for b in values(var.budgets) : b.auto_adjust.enabled ? b.amount == null : coalesce(b.amount, 0) > 0])
    error_message = "budgets.amount: > 0; null with auto_adjust."
  }

  validation {
    condition = alltrue([for b in values(var.budgets) : (
      contains(["COST", "USAGE", "RI_UTILIZATION", "RI_COVERAGE", "SAVINGS_PLANS_UTILIZATION", "SAVINGS_PLANS_COVERAGE"], b.type) &&
      contains(["DAILY", "MONTHLY", "QUARTERLY", "ANNUALLY"], b.time_unit) &&
      contains(["BlendedCost", "UnblendedCost", "AmortizedCost", "NetUnblendedCost", "NetAmortizedCost", "UsageQuantity", "NormalizedUsageAmount", "Hours"], b.metric) &&
      length(b.unit) > 0
    )])
    error_message = "budgets: invalid type, time_unit, metric or unit."
  }

  validation {
    condition = alltrue([for b in values(var.budgets) : length(b.notifications) > 0 && alltrue([for n in b.notifications : (
      contains(["ACTUAL", "FORECASTED"], n.type) &&
      contains(["PERCENTAGE", "ABSOLUTE_VALUE"], n.threshold_type) &&
      contains(["GREATER_THAN", "LESS_THAN", "EQUAL_TO"], n.comparison_operator) &&
      n.threshold > 0
    )])])
    error_message = "budgets.notifications: 1+ valid notifications."
  }

  validation {
    condition = alltrue([for b in values(var.budgets) : (
      alltrue([for k, v in b.filter.tags : length(k) > 0 && length(v) > 0]) &&
      alltrue([for s in b.filter.services : length(s) > 0]) &&
      alltrue([for a in b.filter.linked_accounts : can(regex("^[0-9]{12}$", a))])
    )])
    error_message = "budgets.filter: tag values, services, 12-digit accounts."
  }

  validation {
    condition = alltrue([for b in values(var.budgets) : !b.auto_adjust.enabled || (
      b.auto_adjust.lookback_periods != null &&
      floor(coalesce(b.auto_adjust.lookback_periods, 0)) == coalesce(b.auto_adjust.lookback_periods, 0) &&
      coalesce(b.auto_adjust.lookback_periods, 0) >= 1 &&
      coalesce(b.auto_adjust.lookback_periods, 0) <= try({ DAILY = 60, MONTHLY = 12, QUARTERLY = 4, ANNUALLY = 1 }[b.time_unit], 0)
    )])
    error_message = "budgets.auto_adjust.lookback_periods: 1-60 daily, 1-12 monthly, 1-4 quarterly, 1 annually."
  }
}

variable "anomaly_detection" {
  description = "Cost Anomaly Detection monitors and alert subscriptions."
  type = object({
    enabled = optional(bool, true)
    service_monitor = optional(object({
      create = optional(bool, true)
      arn    = optional(string)
    }), {})
    custom_monitors = optional(map(object({
      linked_accounts = optional(list(string), [])
      tag = optional(object({
        key    = string
        values = list(string)
      }))
      cost_category = optional(object({
        key   = string
        value = string
      }))
    })), {})
    threshold = optional(object({
      absolute   = optional(number)
      percentage = optional(number)
    }), { absolute = 100 })
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.anomaly_detection.service_monitor.create && var.anomaly_detection.service_monitor.arn != null)
    error_message = "anomaly_detection.service_monitor: set create or arn, not both."
  }

  validation {
    condition     = var.anomaly_detection.service_monitor.arn == null || can(regex("^arn:aws[a-z-]*:ce::[0-9]{12}:anomalymonitor/[A-Za-z0-9-]+$", var.anomaly_detection.service_monitor.arn))
    error_message = "anomaly_detection.service_monitor.arn: an anomaly monitor ARN."
  }

  validation {
    condition     = !var.anomaly_detection.enabled || var.anomaly_detection.service_monitor.create || var.anomaly_detection.service_monitor.arn != null || length(var.anomaly_detection.custom_monitors) > 0
    error_message = "anomaly_detection: at least one monitor."
  }

  validation {
    condition     = alltrue([for k in keys(var.anomaly_detection.custom_monitors) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k)) && k != "services"])
    error_message = "anomaly_detection.custom_monitors keys: 1-32 chars, a-z 0-9 -, not services."
  }

  validation {
    condition = alltrue([for m in values(var.anomaly_detection.custom_monitors) : (
      length([for chosen in [length(m.linked_accounts) > 0, m.tag != null, m.cost_category != null] : chosen if chosen]) == 1 &&
      length(m.linked_accounts) <= 10 && alltrue([for a in m.linked_accounts : can(regex("^[0-9]{12}$", a))]) &&
      (m.tag == null || (length(try(m.tag.values, [])) >= 1 && length(try(m.tag.values, [])) <= 10))
    )])
    error_message = "anomaly_detection.custom_monitors: one of linked_accounts (1-10), tag (1-10 values), cost_category."
  }

  validation {
    condition = (
      (var.anomaly_detection.threshold.absolute != null || var.anomaly_detection.threshold.percentage != null) &&
      alltrue([for t in [var.anomaly_detection.threshold.absolute, var.anomaly_detection.threshold.percentage] : t == null || (coalesce(t, 0) >= 0 && coalesce(t, 0) <= 10000000000)])
    )
    error_message = "anomaly_detection.threshold: absolute or percentage, 0-10000000000."
  }
}

variable "cost_allocation_tags" {
  description = "User-defined cost allocation tags to activate."
  type = object({
    enabled = optional(bool, false)
    keys    = optional(list(string), ["Application", "Environment", "ManagedBy"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = (!var.cost_allocation_tags.enabled || length(var.cost_allocation_tags.keys) > 0) && alltrue([for k in var.cost_allocation_tags.keys : length(k) >= 1 && length(k) <= 128])
    error_message = "cost_allocation_tags.keys: 1+ keys, 1-128 chars."
  }
}
