locals {
  scp = var.service_control_policies

  scp_exempt_arns      = distinct(var.exempt_principal_arns)
  security_exempt_arns = distinct(concat(var.exempt_principal_arns, var.security_admin_role_arns))
  network_exempt_arns  = distinct(concat(var.exempt_principal_arns, var.network_admin_role_arns))
  iam_user_exempt_arns = distinct(concat(var.exempt_principal_arns, local.scp.restrict_iam_user_credentials.allowed_principal_arns))

  scp_exempt_condition      = { for k, v in { ArnNotLike = { "aws:PrincipalArn" = local.scp_exempt_arns } } : k => v if length(local.scp_exempt_arns) > 0 }
  security_exempt_condition = { for k, v in { ArnNotLike = { "aws:PrincipalArn" = local.security_exempt_arns } } : k => v if length(local.security_exempt_arns) > 0 }
  network_exempt_condition  = { for k, v in { ArnNotLike = { "aws:PrincipalArn" = local.network_exempt_arns } } : k => v if length(local.network_exempt_arns) > 0 }
  iam_user_exempt_condition = { for k, v in { ArnNotLike = { "aws:PrincipalArn" = local.iam_user_exempt_arns } } : k => v if length(local.iam_user_exempt_arns) > 0 }

  region_restriction_global_actions = [
    "a4b:*", "acm:*", "aws-marketplace-management:*", "aws-marketplace:*", "aws-portal:*", "budgets:*", "ce:*",
    "chime:*", "cloudfront:*", "config:*", "cur:*", "directconnect:*", "ec2:DescribeRegions",
    "ec2:DescribeTransitGateways", "ec2:DescribeVpnGateways", "fms:*", "globalaccelerator:*", "health:*", "iam:*",
    "importexport:*", "kms:*", "mobileanalytics:*", "networkmanager:*", "organizations:*", "pricing:*", "route53:*",
    "route53domains:*", "route53-recovery-cluster:*", "route53-recovery-control-config:*",
    "route53-recovery-readiness:*", "s3:GetAccountPublic*", "s3:ListAllMyBuckets", "s3:ListMultiRegionAccessPoints",
    "s3:PutAccountPublic*", "shield:*", "sts:*", "support:*", "trustedadvisor:*", "waf-regional:*", "waf:*", "wafv2:*",
    "wellarchitected:*",
  ]

  security_service_actions = {
    "access-analyzer" = [
      "access-analyzer:DeleteAnalyzer", "access-analyzer:ApplyArchiveRule", "access-analyzer:CreateArchiveRule",
      "access-analyzer:DeleteArchiveRule", "access-analyzer:UpdateArchiveRule", "access-analyzer:UpdateFindings",
    ]
    cloudtrail = [
      "cloudtrail:DeleteTrail", "cloudtrail:StopLogging", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
      "cloudtrail:DeleteEventDataStore", "cloudtrail:StopEventDataStoreIngestion",
    ]
    config = [
      "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder",
      "config:DeleteServiceLinkedConfigurationRecorder", "config:PutConfigurationRecorder",
      "config:DeleteDeliveryChannel", "config:PutDeliveryChannel", "config:DeleteRetentionConfiguration",
      "config:DeleteConfigurationAggregator", "config:DeleteAggregationAuthorization", "config:DeleteConfigRule",
      "config:DeleteConformancePack", "config:DeleteEvaluationResults",
    ]
    guardduty = [
      "guardduty:DeleteDetector", "guardduty:UpdateDetector", "guardduty:DisassociateFromMasterAccount",
      "guardduty:DisassociateFromAdministratorAccount", "guardduty:DisassociateMembers", "guardduty:DeleteMembers",
      "guardduty:StopMonitoringMembers", "guardduty:DeletePublishingDestination",
      "guardduty:UpdatePublishingDestination",
    ]
    inspector2 = [
      "inspector2:Disable", "inspector2:DisableDelegatedAdminAccount", "inspector2:DisassociateMember",
      "inspector2:UpdateOrganizationConfiguration",
    ]
    macie2 = [
      "macie2:DisableMacie", "macie2:DisableOrganizationAdminAccount", "macie2:DisassociateFromAdministratorAccount",
      "macie2:DisassociateFromMasterAccount", "macie2:DisassociateMember", "macie2:DeleteMember",
      "macie2:UpdateMacieSession", "macie2:UpdateMemberSession",
    ]
    securityhub = [
      "securityhub:DisableSecurityHub", "securityhub:DisableSecurityHubV2", "securityhub:DisassociateFromMasterAccount",
      "securityhub:DisassociateFromAdministratorAccount", "securityhub:DisassociateMembers", "securityhub:DeleteMembers",
      "securityhub:BatchDisableStandards", "securityhub:UpdateStandardsControl",
      "securityhub:UpdateSecurityHubConfiguration", "securityhub:DeleteConfigurationPolicy",
      "securityhub:UpdateOrganizationConfiguration", "securityhub:DisableImportFindingsForProduct",
      "securityhub:DeleteFindingAggregator", "securityhub:DeleteAggregatorV2",
    ]
  }

  kms_protection_tag_condition = {
    "aws:ResourceTag/${local.scp.protect_security_kms_keys.protection_tag_key}" = local.scp.protect_security_kms_keys.protection_tag_value
  }

  audit_bucket_actions = [
    "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:PutBucketPolicy", "s3:PutBucketAcl", "s3:PutBucketOwnershipControls",
    "s3:PutBucketVersioning", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration",
    "s3:PutBucketObjectLockConfiguration", "s3:PutBucketPublicAccessBlock",
  ]

  network_perimeter_actions = [
    "ec2:AttachInternetGateway", "ec2:CreateInternetGateway", "ec2:CreateEgressOnlyInternetGateway",
    "ec2:CreateVpcPeeringConnection", "ec2:AcceptVpcPeeringConnection", "ec2:CreateTransitGatewayVpcAttachment",
    "ec2:AcceptTransitGatewayVpcAttachment", "ec2:CreateVpcEndpoint",
  ]

  iam_user_credential_actions = ["iam:CreateUser", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateAccessKey"]

  ec2_guardrails = local.scp.ec2_guardrails

  scp_statements = {
    deny_leave_organization = [{
      Sid       = "DenyLeaveOrganization"
      Effect    = "Deny"
      Action    = ["organizations:LeaveOrganization"]
      Resource  = "*"
      Condition = local.scp_exempt_condition
    }]

    region_restriction = [{
      Sid       = "DenyOutsideAllowedRegions"
      Effect    = "Deny"
      NotAction = distinct(concat(local.region_restriction_global_actions, local.scp.region_restriction.additional_global_actions))
      Resource  = "*"
      Condition = merge({ StringNotEquals = { "aws:RequestedRegion" = local.scp.region_restriction.allowed_regions } }, local.scp_exempt_condition)
    }]

    root_user_restriction = [{
      Sid      = "DenyMemberRootUserLongTermCredentials"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = merge({
        ArnLike = { "aws:PrincipalArn" = ["arn:${local.partition}:iam::*:root"] }
        Null    = { "aws:AssumedRoot" = "true" }
      }, local.scp_exempt_condition)
    }]

    protect_security_services = [{
      Sid       = "DenyDisablingSecurityServices"
      Effect    = "Deny"
      Action    = flatten([for s in sort(tolist(local.scp.protect_security_services.services)) : local.security_service_actions[s]])
      Resource  = "*"
      Condition = local.security_exempt_condition
    }]

    protect_security_kms_keys = [
      {
        Sid    = "DenyDestructiveActionsOnProtectedKeys"
        Effect = "Deny"
        Action = [
          "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:DisableKeyRotation", "kms:PutKeyPolicy",
          "kms:DeleteImportedKeyMaterial",
        ]
        Resource  = "arn:${local.partition}:kms:*:*:key/*"
        Condition = merge({ StringEquals = local.kms_protection_tag_condition }, local.security_exempt_condition)
      },
      {
        Sid      = "DenyChangingProtectionTag"
        Effect   = "Deny"
        Action   = ["kms:TagResource", "kms:UntagResource"]
        Resource = "arn:${local.partition}:kms:*:*:key/*"
        Condition = merge({
          StringEquals               = local.kms_protection_tag_condition
          "ForAnyValue:StringEquals" = { "aws:TagKeys" = [local.scp.protect_security_kms_keys.protection_tag_key] }
        }, local.security_exempt_condition)
      },
    ]

    protect_audit_buckets = [{
      Sid       = "DenyAuditBucketConfigurationChanges"
      Effect    = "Deny"
      Action    = local.audit_bucket_actions
      Resource  = local.scp.protect_audit_buckets.bucket_arns
      Condition = local.security_exempt_condition
    }]


    ec2_guardrails = concat(
      [for s in [
        {
          Sid       = "DenyRunInstancesWithoutImdsV2"
          Effect    = "Deny"
          Action    = ["ec2:RunInstances"]
          Resource  = "arn:${local.partition}:ec2:*:*:instance/*"
          Condition = merge({ StringNotEquals = { "ec2:MetadataHttpTokens" = "required" } }, local.scp_exempt_condition)
        },
        {
          Sid      = "DenyImdsV1Reenablement"
          Effect   = "Deny"
          Action   = ["ec2:ModifyInstanceMetadataOptions"]
          Resource = "arn:${local.partition}:ec2:*:*:instance/*"
          Condition = merge({
            StringNotEquals = { "ec2:Attribute/HttpTokens" = "required" }
            Null            = { "ec2:Attribute/HttpTokens" = "false" }
          }, local.scp_exempt_condition)
        },
      ] : s if local.ec2_guardrails.require_imdsv2],
      [for s in [{
        Sid       = "DenyUnencryptedVolumes"
        Effect    = "Deny"
        Action    = ["ec2:RunInstances", "ec2:CreateVolume"]
        Resource  = "arn:${local.partition}:ec2:*:*:volume/*"
        Condition = merge({ Bool = { "ec2:Encrypted" = "false" } }, local.scp_exempt_condition)
      }] : s if local.ec2_guardrails.require_encrypted_volumes],
      [for s in [{
        Sid       = "DenyDisablingEbsEncryptionByDefault"
        Effect    = "Deny"
        Action    = ["ec2:DisableEbsEncryptionByDefault"]
        Resource  = "*"
        Condition = local.scp_exempt_condition
      }] : s if local.ec2_guardrails.deny_disable_ebs_default_encryption],
      [for s in [{
        Sid       = "DenyPublicIpOnLaunch"
        Effect    = "Deny"
        Action    = ["ec2:RunInstances"]
        Resource  = "arn:${local.partition}:ec2:*:*:network-interface/*"
        Condition = merge({ Bool = { "ec2:AssociatePublicIpAddress" = "true" } }, local.scp_exempt_condition)
      }] : s if local.ec2_guardrails.deny_public_ip],
      [for s in [{
        Sid       = "DenyUnapprovedInstanceTypes"
        Effect    = "Deny"
        Action    = ["ec2:RunInstances"]
        Resource  = "arn:${local.partition}:ec2:*:*:instance/*"
        Condition = merge({ StringNotLike = { "ec2:InstanceType" = local.ec2_guardrails.allowed_instance_types } }, local.scp_exempt_condition)
      }] : s if length(local.ec2_guardrails.allowed_instance_types) > 0],
    )

    network_guardrails = [{
      Sid       = "DenyUnapprovedNetworkPerimeterChanges"
      Effect    = "Deny"
      Action    = local.network_perimeter_actions
      Resource  = "*"
      Condition = local.network_exempt_condition
    }]

    restrict_iam_user_credentials = [{
      Sid       = "DenyIamUserLongLivedCredentials"
      Effect    = "Deny"
      Action    = local.iam_user_credential_actions
      Resource  = "arn:${local.partition}:iam::*:user/*"
      Condition = local.iam_user_exempt_condition
    }]
  }

  scp_documents = { for k, stmts in local.scp_statements : k => jsonencode({
    Version   = "2012-10-17"
    Statement = [for s in stmts : { for ek, ev in s : ek => ev if ek != "Condition" || length(ev) > 0 }]
  }) }

  scp_descriptions = {
    deny_leave_organization       = "Denies organizations:LeaveOrganization."
    region_restriction            = "Denies requests outside the allowed Regions, except global services."
    root_user_restriction         = "Denies member-account root users with long-term credentials; sts:AssumeRoot sessions stay usable."
    protect_security_services     = "Denies disabling security services except for security admin roles."
    protect_security_kms_keys     = "Denies deletion, disablement and key policy or tag changes on protected KMS keys."
    protect_audit_buckets         = "Denies deletion and configuration changes on audit buckets."
    ec2_guardrails                = "Denies EC2 launches without IMDSv2 or with unencrypted volumes."
    network_guardrails            = "Limits network perimeter changes to network admin roles."
    restrict_iam_user_credentials = "Denies creating IAM users, console passwords and access keys."
  }

  scp_library = { for k, p in local.scp : k => {
    type        = "SERVICE_CONTROL_POLICY"
    targets     = p.targets
    description = local.scp_descriptions[k]
    content     = local.scp_documents[k]
  } }
}
