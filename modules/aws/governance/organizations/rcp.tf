locals {
  rcp = var.resource_control_policies

  identity_perimeter_sts_actions = [
    "sts:AssumeRole", "sts:DecodeAuthorizationMessage", "sts:GetAccessKeyInfo", "sts:GetFederationToken",
    "sts:GetServiceBearerToken", "sts:GetSessionToken", "sts:SetContext",
  ]

  identity_perimeter_actions = flatten([
    for s in distinct(local.rcp.identity_perimeter.services) : s == "sts" ? local.identity_perimeter_sts_actions : ["${s}:*"]
  ])

  trusted_accounts_principal_condition = { for k, v in { "aws:PrincipalAccount" = local.rcp.identity_perimeter.trusted_account_ids } : k => v if length(v) > 0 }
  trusted_accounts_source_condition    = { for k, v in { "aws:SourceAccount" = local.rcp.identity_perimeter.trusted_account_ids } : k => v if length(v) > 0 }

  rcp_statements = {
    transport_security = concat(
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = [for s in distinct(local.rcp.transport_security.services) : "${s}:*"]
        Resource  = "*"
        Condition = {
          BoolIfExists = {
            "aws:SecureTransport"       = "false"
            "aws:PrincipalIsAWSService" = "false"
          }
        }
      }],
      [for s in [{
        Sid       = "DenyS3TlsBelow12"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:*"]
        Resource  = "*"
        Condition = {
          NumericLessThan = { "s3:TlsVersion" = ["1.2"] }
          BoolIfExists    = { "aws:PrincipalIsAWSService" = "false" }
        }
      }] : s if contains(local.rcp.transport_security.services, "s3")],
    )

    identity_perimeter = [
      {
        Sid       = "EnforceOrgIdentities"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.identity_perimeter_actions
        Resource  = "*"
        Condition = {
          StringNotEqualsIfExists = merge({ "aws:PrincipalOrgID" = local.organization_id }, local.trusted_accounts_principal_condition)
          BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }
        }
      },
      {
        Sid       = "EnforceConfusedDeputyProtection"
        Effect    = "Deny"
        Principal = "*"
        Action    = [for s in distinct(local.rcp.identity_perimeter.services) : "${s}:*"]
        Resource  = "*"
        Condition = {
          StringNotEqualsIfExists = merge({ "aws:SourceOrgID" = local.organization_id }, local.trusted_accounts_source_condition)
          Null                    = { "aws:SourceAccount" = "false" }
          Bool                    = { "aws:PrincipalIsAWSService" = "true" }
        }
      },
    ]
  }

  rcp_documents = { for k, stmts in local.rcp_statements : k => jsonencode({
    Version   = "2012-10-17"
    Statement = stmts
  }) }

  rcp_descriptions = {
    transport_security = "Denies non-TLS requests and S3 requests below TLS 1.2 to member-account resources."
    identity_perimeter = "Denies access to member-account resources from outside the organization."
  }

  rcp_library = { for k, p in local.rcp : k => {
    type        = "RESOURCE_CONTROL_POLICY"
    targets     = p.targets
    description = local.rcp_descriptions[k]
    content     = local.rcp_documents[k]
  } }
}
