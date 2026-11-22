locals {
  partition       = module.naming.partition
  organization_id = data.aws_organizations_organization.current.id
  root            = data.aws_organizations_organization.current.roots[0]
  root_id         = local.root.id

  target_pattern = "^(root|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|[0-9]{12})$"

  current_enabled_policy_types = toset([for p in local.root.policy_types : p.type if p.status == "ENABLED"])
  current_active_policy_types  = toset([for p in local.root.policy_types : p.type if p.status != "PENDING_DISABLE"])

  managed_policy_types = toset(concat(
    [for p in values(local.policies) : p.type],
    tolist(var.organization.additional_policy_types),
  ))

  effective_policy_types  = var.organization.manage ? local.managed_policy_types : local.current_enabled_policy_types
  policy_types_to_disable = setsubtract(local.current_active_policy_types, local.managed_policy_types)

  service_owned_principals = {
    "cloudtrail.amazonaws.com"               = "modules/aws/security/cloudtrail"
    "config.amazonaws.com"                   = "modules/aws/security/config"
    "config-multiaccountsetup.amazonaws.com" = "modules/aws/security/config"
    "securityhub.amazonaws.com"              = "modules/aws/security/security-hub"
    "inspector2.amazonaws.com"               = "modules/aws/security/inspector"
    "access-analyzer.amazonaws.com"          = "modules/aws/security/iam-access-analyzer"
    "guardduty.amazonaws.com"                = "modules/aws/security/guardduty"
    "detective.amazonaws.com"                = "modules/aws/security/detective"
    "backup.amazonaws.com"                   = "modules/aws/storage/backup"
    "ssm.amazonaws.com"                      = "modules/aws/governance/systems-manager"
  }

  trusted_access_principals = toset(concat(
    tolist(var.trusted_access_service_principals),
    var.root_access_management.enabled ? ["iam.amazonaws.com"] : [],
  ))

  provider_policy_types = [
    "SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY", "AISERVICES_OPT_OUT_POLICY",
    "CHATBOT_POLICY", "DECLARATIVE_POLICY_EC2", "SECURITYHUB_POLICY", "INSPECTOR_POLICY", "UPGRADE_ROLLOUT_POLICY",
    "BEDROCK_POLICY", "S3_POLICY", "NETWORK_SECURITY_DIRECTOR_POLICY", "GUARDDUTY_POLICY",
  ]

  policy_types = [
    "SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "TAG_POLICY", "AISERVICES_OPT_OUT_POLICY", "CHATBOT_POLICY",
    "DECLARATIVE_POLICY_EC2", "UPGRADE_ROLLOUT_POLICY", "BEDROCK_POLICY", "S3_POLICY", "NETWORK_SECURITY_DIRECTOR_POLICY",
  ]

  policy_type_paths = {
    SERVICE_CONTROL_POLICY           = "service_control_policy"
    RESOURCE_CONTROL_POLICY          = "resource_control_policy"
    TAG_POLICY                       = "tag_policy"
    AISERVICES_OPT_OUT_POLICY        = "aiservices_opt_out_policy"
    CHATBOT_POLICY                   = "chatbot_policy"
    DECLARATIVE_POLICY_EC2           = "declarative_policy_ec2"
    UPGRADE_ROLLOUT_POLICY           = "upgrade_rollout_policy"
    BEDROCK_POLICY                   = "bedrock_policy"
    S3_POLICY                        = "s3_policy"
    NETWORK_SECURITY_DIRECTOR_POLICY = "network_security_director_policy"
  }

  policy_size_limits = {
    SERVICE_CONTROL_POLICY           = 10240
    RESOURCE_CONTROL_POLICY          = 5120
    AISERVICES_OPT_OUT_POLICY        = 2500
    TAG_POLICY                       = 10000
    CHATBOT_POLICY                   = 10000
    DECLARATIVE_POLICY_EC2           = 10000
    UPGRADE_ROLLOUT_POLICY           = 10000
    BEDROCK_POLICY                   = 10000
    S3_POLICY                        = 10000
    NETWORK_SECURITY_DIRECTOR_POLICY = 10000
  }

  policy_attachment_limits = {
    SERVICE_CONTROL_POLICY    = 9
    RESOURCE_CONTROL_POLICY   = 4
    AISERVICES_OPT_OUT_POLICY = 5
    CHATBOT_POLICY            = 5
  }

  rcp_supported_service_prefixes = [
    "appflow", "app-integrations", "appstream", "dsql", "clouddirectory", "cloudfront", "cloudsearch", "cloudwatch",
    "internetmonitor", "logs", "networkmonitor", "rum", "cognito-identity", "cognito-idp", "comprehend",
    "comprehendmedical", "firehose", "devops-guru", "dynamodb", "dax", "autoscaling", "ebs", "ecr", "ecr-public",
    "elasticfilesystem", "schemas", "gamelift", "inspector-scan", "kendra", "kinesisvideo", "lexv2-runtime", "macie2",
    "managedblockchain", "grafana", "memorydb", "aoss", "personalize", "polly", "s3", "securitylake", "sns", "swf",
    "sqs", "textract", "timestream-influxdb", "transcribe", "translate", "workspaces", "amplify", "appconfig",
    "application-autoscaling", "auditmanager", "autoscaling-plans", "budgets", "cleanrooms", "servicediscovery",
    "cloudtrail-data", "codeartifact", "codebuild", "codecommit", "codepipeline", "compute-optimizer",
    "cost-optimization-hub", "events", "fms", "fis", "health", "rolesanywhere", "kms", "refactor-spaces", "opensearch",
    "pricing", "pca-connector-ad", "resiliencehub", "resource-groups", "secretsmanager", "ssm-incidents", "sts",
    "signin", "signer", "support", "transfer", "notifications", "wafv2", "xray",
  ]

  library_targets = merge(
    { for k, p in var.service_control_policies : k => p.targets },
    { for k, p in var.resource_control_policies : k => p.targets },
    { for k, p in var.declarative_policies : k => p.targets },
  )

  library_policy_keys = keys(local.library_targets)

  policy_keys = concat(
    [for k, t in local.library_targets : k if length(t) > 0],
    keys(var.custom_policies),
  )

  library_policies = merge(local.scp_library, local.rcp_library, local.declarative_library)

  policies = merge(
    { for k, p in local.library_policies : k => p if length(p.targets) > 0 },
    { for k, p in var.custom_policies : k => {
      type        = p.type
      description = coalesce(p.description, "Custom ${p.type}.")
      content     = p.content
      targets     = p.targets
    } },
  )

  policy_names = { for k in local.policy_keys : k => module.naming.names[k] }

  policy_statements = { for k, p in local.policies : k => try(flatten([jsondecode(p.content).Statement]), []) if contains(["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"], p.type) }

  rcp_shape_valid = { for k, p in local.policies : k => try(length(local.policy_statements[k]) > 0 && alltrue([
    for s in local.policy_statements[k] : s.Effect == "Deny" && s.Principal == "*" && alltrue([
      for a in flatten([s.Action]) : a != "*" && contains(local.rcp_supported_service_prefixes, split(":", a)[0])
    ])
  ]), false) if p.type == "RESOURCE_CONTROL_POLICY" }

  attachments = { for a in flatten([
    for k, p in local.policies : [
      for t in distinct(p.targets) : {
        key        = "${k}/${t}"
        policy_key = k
        type       = p.type
        target_id  = t == "root" ? local.root_id : t
      }
    ]
  ]) : a.key => a }

  attachments_per_type_target = { for a in values(local.attachments) : "${a.type}|${a.target_id}" => a.key... }

  delegation_types     = sort(tolist(var.policy_management_delegation.policy_types))
  delegation_principal = var.policy_management_delegation.account_id == null ? "" : "arn:${local.partition}:iam::${var.policy_management_delegation.account_id}:root"
  management_account   = data.aws_organizations_organization.current.master_account_id
  delegation_policy_arns = [
    for t in local.delegation_types : "arn:${local.partition}:organizations::${local.management_account}:policy/${local.organization_id}/${local.policy_type_paths[t]}/*"
  ]

  delegation_policy_content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DelegatingNecessaryDescribeListActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegation_principal }
        Action = [
          "organizations:DescribeOrganization", "organizations:DescribeOrganizationalUnit",
          "organizations:DescribeAccount", "organizations:ListRoots", "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListParents", "organizations:ListChildren", "organizations:ListAccounts",
          "organizations:ListAccountsForParent", "organizations:ListTagsForResource",
        ]
        Resource = "*"
      },
      {
        Sid       = "DelegatingPolicyReadActions"
        Effect    = "Allow"
        Principal = { AWS = local.delegation_principal }
        Action = [
          "organizations:DescribePolicy", "organizations:DescribeEffectivePolicy", "organizations:ListPolicies",
          "organizations:ListPoliciesForTarget", "organizations:ListTargetsForPolicy",
        ]
        Resource  = "*"
        Condition = { StringLikeIfExists = { "organizations:PolicyType" = local.delegation_types } }
      },
      {
        Sid       = "DelegatingPolicyManagement"
        Effect    = "Allow"
        Principal = { AWS = local.delegation_principal }
        Action = [
          "organizations:CreatePolicy", "organizations:UpdatePolicy", "organizations:DeletePolicy",
          "organizations:AttachPolicy", "organizations:DetachPolicy",
        ]
        Resource = concat([
          local.root.arn,
          "arn:${local.partition}:organizations::${local.management_account}:ou/${local.organization_id}/*",
          "arn:${local.partition}:organizations::${local.management_account}:account/${local.organization_id}/*",
        ], local.delegation_policy_arns)
        Condition = { StringLikeIfExists = { "organizations:PolicyType" = local.delegation_types } }
      },
      {
        Sid       = "DelegatingPolicyTagging"
        Effect    = "Allow"
        Principal = { AWS = local.delegation_principal }
        Action    = ["organizations:TagResource", "organizations:UntagResource"]
        Resource  = local.delegation_policy_arns
      },
    ]
  })
}
