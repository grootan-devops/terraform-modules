locals {
  partition      = module.naming.partition
  arn_prefix     = "arn:${local.partition}"
  region         = module.naming.region
  account_id     = module.naming.account_id
  dns_suffix     = module.naming.dns_suffix
  cluster_name   = module.naming.names.cluster
  cluster_arn    = "${local.arn_prefix}:eks:${local.region}:${local.account_id}:cluster/${local.cluster_name}"
  kms_key_arn    = module.encryption.key_arn
  kms_encrypted  = var.kms.create || var.kms.key_id != null
  logs_enabled   = length(var.cloudwatch_logs.log_types) > 0
  log_group_name = "/aws/eks/${local.cluster_name}/cluster"
  log_group_arn  = "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"
  has_nodes      = length(var.node_groups) > 0
  node_role_arn  = var.iam_role.create ? try(module.node_role[0].arn, null) : var.iam_role.arn
  addons_enabled = var.addons.enabled
  s3_csi_enabled = local.addons_enabled && length(var.addons.s3_csi_bucket_arns) > 0
  insights       = local.addons_enabled && var.container_insights.enabled

  insights_log_groups = local.insights ? toset(["application", "dataplane", "host", "performance"]) : toset([])
  insights_log_names  = { for t in local.insights_log_groups : t => "/aws/containerinsights/${local.cluster_name}/${t}" }
  kms_log_group_arns = concat(
    local.logs_enabled ? [local.log_group_arn] : [],
    [for t, n in local.insights_log_names : "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:${n}"],
  )

  security_group_ids = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)

  names = merge(
    { cluster = { max_length = 100 } },
    { for k in keys(var.node_groups) : "ng-${k}" => { suffix = k, max_length = 37 } },
    { for k in keys(var.fargate_profiles) : "fp-${k}" => { suffix = k, max_length = 63 } }
  )

  api_ingress_rules = merge(
    { for i, sg in var.security_group.ingress_security_group_ids : "sg-${i}" => { description = "Kubernetes API from a security group", from_port = 443, to_port = 443, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.ingress_cidr_blocks : "cidr-${i}" => { description = "Kubernetes API from ${cidr}", from_port = 443, to_port = 443, cidr_ipv4 = cidr } },
    { for i, pl in var.security_group.ingress_prefix_list_ids : "pl-${i}" => { description = "Kubernetes API from a prefix list", from_port = 443, to_port = 443, prefix_list_id = pl } }
  )

  api_egress_rules = { for i, cidr in var.security_group.egress_cidr_blocks : "cidr-${i}" => { description = "Outbound to ${cidr}", ip_protocol = "-1", cidr_ipv4 = cidr } }

  kms_service_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "AllowClusterSecretsEncryption"
        actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ListGrants", "kms:DescribeKey", "kms:CreateGrant"]
        principals = { AWS = [module.cluster_role.arn] }
        conditions = []
      }
    },
    {
      when = local.logs_enabled || local.insights
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${local.region}.${local.dns_suffix}"] }
        conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = local.kms_log_group_arns }]
      }
    },
    {
      when = local.has_nodes || local.addons_enabled
      statement = {
        sid        = "AllowEbsThroughEc2"
        actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey"]
        principals = { AWS = ["*"] }
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["ec2.${local.region}.${local.dns_suffix}"] }
        ]
      }
    }
  ]

  kms_service_statements = [for c in local.kms_service_statement_candidates : c.statement if c.when]

  node_managed_policy_arns = concat(
    [
      "${local.arn_prefix}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "${local.arn_prefix}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    ],
    local.addons_enabled ? [] : ["${local.arn_prefix}:iam::aws:policy/AmazonEKS_CNI_Policy"],
    var.iam_role.managed_policy_arns
  )

  default_addon_configuration = {
    vpc-cni            = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } })
    coredns            = jsonencode({ replicaCount = 2 })
    aws-ebs-csi-driver = jsonencode({ controller = { replicaCount = 2 } })
    aws-efs-csi-driver = jsonencode({ controller = { replicaCount = 2 } })
  }

  addon_configuration = merge(local.default_addon_configuration, var.addons.configuration_values)

  addon_roles = merge(
    {
      vpc-cni      = ["${local.arn_prefix}:iam::aws:policy/AmazonEKS_CNI_Policy"]
      ebs-csi      = ["${local.arn_prefix}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
      efs-csi      = ["${local.arn_prefix}:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]
      efs-csi-node = []
    },
    local.s3_csi_enabled ? { s3-csi = [] } : {},
    local.insights ? { cloudwatch-agent = ["${local.arn_prefix}:iam::aws:policy/CloudWatchAgentServerPolicy"] } : {}
  )

  addon_role_documents = {
    efs-csi-node = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "MountThroughMountTargets"
        Effect    = "Allow"
        Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
        Resource  = ["${local.arn_prefix}:elasticfilesystem:${local.region}:${local.account_id}:file-system/*"]
        Condition = { Bool = { "elasticfilesystem:AccessedViaMountTarget" = "true" } }
      }]
    })
    s3-csi = local.s3_csi_policy
  }

  addon_associations = {
    vpc-cni                         = { aws-node = "vpc-cni" }
    aws-ebs-csi-driver              = { ebs-csi-controller-sa = "ebs-csi" }
    aws-efs-csi-driver              = { efs-csi-controller-sa = "efs-csi", efs-csi-node-sa = "efs-csi-node" }
    aws-mountpoint-s3-csi-driver    = { s3-csi-driver-sa = "s3-csi" }
    amazon-cloudwatch-observability = { cloudwatch-agent = "cloudwatch-agent" }
  }

  addons_before_compute = local.addons_enabled ? toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"]) : toset([])
  addons_after_compute = local.addons_enabled ? toset(concat(
    ["coredns", "aws-ebs-csi-driver", "aws-efs-csi-driver", "snapshot-controller"],
    local.s3_csi_enabled ? ["aws-mountpoint-s3-csi-driver"] : [],
    local.insights ? ["amazon-cloudwatch-observability"] : []
  )) : toset([])

  s3_csi_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for c in [
      {
        when = true
        statement = {
          Sid      = "MountpointListBuckets"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = var.addons.s3_csi_bucket_arns
        }
      },
      {
        when = true
        statement = {
          Sid      = "MountpointObjectAccess"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:DeleteObject"]
          Resource = [for arn in var.addons.s3_csi_bucket_arns : "${arn}/*"]
        }
      },
      {
        when = length(var.addons.s3_csi_kms_key_arns) > 0
        statement = {
          Sid       = "MountpointSseKms"
          Effect    = "Allow"
          Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
          Resource  = var.addons.s3_csi_kms_key_arns
          Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.${local.dns_suffix}" } }
        }
      }
    ] : c.statement if c.when]
  })

  workload_roles = { for k, p in var.pod_identities : k => p if length(p.policy_statements) + length(p.managed_policy_arns) > 0 }

  access_policy_associations = merge([
    for ek, e in var.access_entries : {
      for pk, p in e.policy_associations : "${ek}/${pk}" => {
        entry         = ek
        principal_arn = e.principal_arn
        policy_arn    = startswith(p.policy, "arn:") ? p.policy : "${local.arn_prefix}:eks::aws:cluster-access-policy/${p.policy}"
        namespaces    = p.namespaces
      }
    }
  ]...)

  elb_arn = "arn:${local.partition}:elasticloadbalancing:${local.region}:*"
  ec2_arn = "arn:${local.partition}:ec2:${local.region}:*"

  lbc_sg_arns          = ["${local.ec2_arn}:security-group/*"]
  lbc_sg_and_rule_arns = ["${local.ec2_arn}:security-group*"]
  lbc_lb_tg_arns       = ["${local.elb_arn}:loadbalancer/*", "${local.elb_arn}:targetgroup/*"]
  lbc_listener_arns    = ["${local.elb_arn}:listener/*", "${local.elb_arn}:listener-rule/*"]
  lbc_tag_request      = "aws:RequestTag/elbv2.k8s.aws/cluster"
  lbc_tag_resource     = "aws:ResourceTag/elbv2.k8s.aws/cluster"

  lb_controller_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ElbServiceLinkedRole"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Sid    = "NoResourceArns"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:DescribeCoipPools",
          "ec2:DescribeIpamPools",
          "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation",
          "elasticloadbalancing:SetWebAcl",
          "acm:ListCertificates",
          "iam:ListServerCertificates",
          "shield:GetSubscriptionState",
          "shield:CreateProtection"
        ]
        Resource = "*"
      },
      {
        Sid    = "Scoped"
        Effect = "Allow"
        Action = [
          "ec2:GetCoipPoolUsage",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:ValidateSecurityGroupQuotasForInterface",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:SetRulePriorities",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "cognito-idp:DescribeUserPoolClient",
          "acm:DescribeCertificate",
          "iam:GetServerCertificate",
          "shield:DescribeProtection",
          "shield:DeleteProtection",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL"
        ]
        Resource = concat(local.lbc_sg_and_rule_arns, local.lbc_lb_tg_arns, local.lbc_listener_arns, [
          "${local.ec2_arn}:vpc/*",
          "${local.ec2_arn}:coip-pool/*",
          "arn:${local.partition}:cognito-idp:${local.region}:${local.account_id}:userpool/*",
          "arn:${local.partition}:acm:${local.region}:${local.account_id}:certificate/*",
          "arn:${local.partition}:iam::${local.account_id}:server-certificate/*",
          "arn:${local.partition}:shield::${local.account_id}:protection/*",
          "arn:${local.partition}:waf-regional:${local.region}:${local.account_id}:webacl/*",
          "arn:${local.partition}:wafv2:${local.region}:${local.account_id}:regional/webacl/*"
        ])
      },
      {
        Sid      = "TagSgOnCreate"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = local.lbc_sg_arns
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            (local.lbc_tag_request) = "false"
          }
        }
      },
      {
        Sid      = "CreateTagged"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = local.lbc_lb_tg_arns
        Condition = {
          Null = {
            (local.lbc_tag_request) = "false"
          }
        }
      },
      {
        Sid      = "TagLbOnCreate"
        Effect   = "Allow"
        Action   = "elasticloadbalancing:AddTags"
        Resource = local.lbc_lb_tg_arns
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = {
            (local.lbc_tag_request) = "false"
          }
        }
      },
      {
        Sid      = "RetagOwned"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags", "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = concat(local.lbc_sg_arns, local.lbc_lb_tg_arns)
        Condition = {
          Null = {
            (local.lbc_tag_request)  = "true"
            (local.lbc_tag_resource) = "false"
          }
        }
      },
      {
        Sid      = "TagListeners"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = local.lbc_listener_arns
      },
      {
        Sid    = "ModifyOwned"
        Effect = "Allow"
        Action = [
          "ec2:DeleteSecurityGroup",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes",
          "elasticloadbalancing:ModifyCapacityReservation",
          "elasticloadbalancing:ModifyIpPools"
        ]
        Resource = concat(local.lbc_sg_arns, local.lbc_lb_tg_arns, local.lbc_listener_arns)
        Condition = {
          Null = {
            (local.lbc_tag_resource) = "false"
          }
        }
      }
    ]
  })
}
