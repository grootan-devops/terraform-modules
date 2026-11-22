variable "application" {
  description = "Application name."
  type        = string

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

variable "name" {
  description = "Cluster name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "cluster_version" {
  description = "Kubernetes minor version, e.g. 1.37."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version: a minor version such as 1.37."
  }
}

variable "upgrade_support_type" {
  description = "STANDARD or EXTENDED support."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.upgrade_support_type)
    error_message = "upgrade_support_type: STANDARD or EXTENDED."
  }
}

variable "deletion_protection" {
  description = "Block cluster deletion."
  type        = bool
  default     = true
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane and, by default, the nodes."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two subnets."
  }
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to the public API endpoint. Empty: private endpoint only."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : !endswith(c, "/0")])
    error_message = "endpoint_public_access_cidrs: no /0 (EKS.1)."
  }
}

variable "security_group" {
  description = "Extra control plane security group: API (443) ingress sources and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), [])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !contains(var.security_group.ingress_cidr_blocks, "0.0.0.0/0") && !contains(var.security_group.ingress_cidr_blocks, "::/0")
    error_message = "security_group.ingress_cidr_blocks: no 0.0.0.0/0 or ::/0."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Admin access entry for the cluster creator."
  type        = bool
  default     = true
  nullable    = false
}

variable "access_entries" {
  description = "Access entries by key: principal, Kubernetes groups and access policies."
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    policy_associations = optional(map(object({
      policy     = string
      namespaces = optional(list(string), [])
    })), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for e in values(var.access_entries) : contains(["STANDARD", "EC2_LINUX", "EC2_WINDOWS", "FARGATE_LINUX", "EC2", "HYBRID_LINUX", "HYPERPOD_LINUX"], e.type)])
    error_message = "access_entries[*].type: an EKS access entry type."
  }
}

variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "cloudwatch_logs" {
  description = "Control plane log types and their log group."
  type = object({
    log_types                   = optional(list(string), ["api", "audit", "authenticator", "controllerManager", "scheduler"])
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for t in var.cloudwatch_logs.log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "cloudwatch_logs.log_types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "iam_role" {
  description = "Node role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.iam_role.create || var.iam_role.arn != null
    error_message = "iam_role: set arn when create = false."
  }
}

variable "node_groups" {
  description = "Managed node groups by key."
  type = map(object({
    instance_types  = list(string)
    subnet_ids      = optional(list(string), [])
    ami_type        = optional(string, "AL2023_x86_64_STANDARD")
    capacity_type   = optional(string, "ON_DEMAND")
    release_version = optional(string)
    min_size        = optional(number, 1)
    max_size        = optional(number, 3)
    desired_size    = optional(number)
    max_unavailable = optional(number, 1)
    disk_size       = optional(number, 50)
    disk_iops       = optional(number)
    disk_throughput = optional(number)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.node_groups) : can(regex("^[a-z0-9][a-z0-9-]{0,23}$", k))])
    error_message = "node_groups keys: 1-24 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for n in values(var.node_groups) : contains(["ON_DEMAND", "SPOT", "CAPACITY_BLOCK"], n.capacity_type)])
    error_message = "node_groups[*].capacity_type: ON_DEMAND, SPOT or CAPACITY_BLOCK."
  }

  validation {
    condition     = alltrue([for n in values(var.node_groups) : n.min_size >= 0 && n.min_size <= n.max_size && n.max_size >= 1 && (n.desired_size == null || (coalesce(n.desired_size, 0) >= n.min_size && coalesce(n.desired_size, 0) <= n.max_size))])
    error_message = "node_groups: 0 <= min_size <= desired_size <= max_size, max_size >= 1."
  }

  validation {
    condition     = alltrue(flatten([for n in values(var.node_groups) : [for t in n.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect)]]))
    error_message = "node_groups[*].taints[*].effect: NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }

  validation {
    condition     = alltrue([for n in values(var.node_groups) : length(n.instance_types) > 0])
    error_message = "node_groups[*].instance_types: at least one."
  }

  validation {
    condition     = alltrue([for n in values(var.node_groups) : !startswith(n.ami_type, "AL2_")])
    error_message = "node_groups[*].ami_type: AL2 AMIs are retired; use AL2023_*, BOTTLEROCKET_* or WINDOWS_*."
  }
}

variable "fargate_profiles" {
  description = "Fargate profiles by key: selectors and optional subnets."
  type = map(object({
    subnet_ids = optional(list(string), [])
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.fargate_profiles) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "fargate_profiles keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for p in values(var.fargate_profiles) : length(p.selectors) >= 1 && length(p.selectors) <= 5])
    error_message = "fargate_profiles[*].selectors: 1-5."
  }
}

variable "addons" {
  description = "Default add-ons with Pod Identity roles, Load Balancer Controller role and S3 CSI driver."
  type = object({
    enabled              = optional(bool, true)
    versions             = optional(map(string), {})
    configuration_values = optional(map(string), {})
    s3_csi_bucket_arns   = optional(list(string), [])
    s3_csi_kms_key_arns  = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in concat(keys(var.addons.versions), keys(var.addons.configuration_values)) : contains(["vpc-cni", "kube-proxy", "eks-pod-identity-agent", "coredns", "aws-ebs-csi-driver", "aws-efs-csi-driver", "snapshot-controller", "aws-mountpoint-s3-csi-driver", "amazon-cloudwatch-observability"], k)])
    error_message = "addons: keys must be module add-on names."
  }

  validation {
    condition     = alltrue([for arn in var.addons.s3_csi_bucket_arns : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", arn))])
    error_message = "addons.s3_csi_bucket_arns: bucket ARNs."
  }
}

variable "container_insights" {
  description = "Container Insights through the CloudWatch Observability add-on."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.container_insights.enabled || var.addons.enabled
    error_message = "container_insights: needs addons.enabled."
  }
}

variable "pod_identities" {
  description = "Workload Pod Identity associations by key: role_arn, or statements for a module role."
  type = map(object({
    namespace           = string
    service_account     = string
    role_arn            = optional(string)
    managed_policy_arns = optional(list(string), [])
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.pod_identities) : can(regex("^[a-z0-9][a-z0-9-]{0,27}$", k))])
    error_message = "pod_identities keys: 1-28 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for p in values(var.pod_identities) : (p.role_arn == null) == (length(p.policy_statements) + length(p.managed_policy_arns) > 0)])
    error_message = "pod_identities: set role_arn or policy statements, not both."
  }
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      cluster = optional(object({
        node_cpu     = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        node_memory  = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        failed_nodes = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      }), {})
      node_groups = optional(object({
        cpu                 = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        status_check_failed = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
