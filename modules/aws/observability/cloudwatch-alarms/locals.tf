locals {
  base_name         = module.naming.name
  cloudfront_region = "us-east-1"

  log_metrics_namespace = "${local.base_name}/LogMetrics"

  rds_free_storage_percent = 20
  bytes_per_gib            = 1073741824

  preset_names = [
    "alarms",
    "lambda_functions",
    "api_gateways",
    "albs",
    "nlbs",
    "http_apis",
    "ecs_services",
    "eks_clusters",
    "auto_scaling_groups",
    "rds_instances",
    "rds_proxies",
    "dynamodb_tables",
    "elasticache_clusters",
    "sqs_queues",
    "eventbridge_rules",
    "schedule_groups",
    "step_functions",
    "cloudfront_distributions",
    "efs_file_systems",
    "waf_web_acls",
    "s3_buckets",
    "nat_gateways",
    "log_metric_filters",
    "cis_cloudtrail_metric_filters",
  ]

  custom_alarm_specs = {
    for k, a in var.alarms : k => {
      preset              = "alarms"
      enabled             = a.enabled
      severity            = a.severity
      description         = a.description
      region              = a.region
      comparison_operator = a.comparison_operator
      threshold           = a.threshold
      evaluation_periods  = a.evaluation_periods
      datapoints_to_alarm = a.datapoints_to_alarm
      period              = a.period
      treat_missing_data  = a.treat_missing_data
      namespace           = a.namespace
      metric_name         = a.metric_name
      dimensions          = a.dimensions
      statistic           = a.statistic
      extended_statistic  = a.extended_statistic
      unit                = a.unit
      queries = [
        for q in a.metric_queries : {
          id          = q.id
          expression  = q.expression
          label       = q.label
          return_data = q.return_data
          period      = q.period
          metric = q.metric == null ? null : {
            namespace   = q.metric.namespace
            metric_name = q.metric.metric_name
            dimensions  = q.metric.dimensions
            stat        = q.metric.stat
            period      = coalesce(q.metric.period, a.period)
            unit        = q.metric.unit
          }
        }
      ]
    }
  }

  preset_alarm_defs = concat(
    local.lambda_alarm_defs,
    local.apigw_alarm_defs,
    local.alb_alarm_defs,
    local.nlb_alarm_defs,
    local.http_api_alarm_defs,
    local.ecs_alarm_defs,
    local.eks_alarm_defs,
    local.asg_alarm_defs,
    local.rds_alarm_defs,
    local.rds_proxy_alarm_defs,
    local.dynamodb_alarm_defs,
    local.elasticache_alarm_defs,
    local.sqs_alarm_defs,
    local.eventbridge_alarm_defs,
    local.scheduler_alarm_defs,
    local.sfn_alarm_defs,
    local.cloudfront_alarm_defs,
    local.efs_alarm_defs,
    local.waf_alarm_defs,
    local.s3_alarm_defs,
    local.nat_alarm_defs,
    local.log_filter_alarm_defs,
    local.cis_alarm_defs,
  )

  preset_alarm_groups = { for d in local.preset_alarm_defs : d.key => d... }

  preset_alarm_specs = {
    for key, group in local.preset_alarm_groups : key => {
      preset              = group[0].preset
      enabled             = group[0].enabled
      severity            = group[0].cfg.severity
      description         = group[0].description
      region              = group[0].region
      comparison_operator = group[0].comparison_operator
      threshold           = group[0].threshold
      evaluation_periods  = group[0].cfg.evaluation_periods
      datapoints_to_alarm = group[0].cfg.datapoints_to_alarm
      period              = group[0].cfg.period
      treat_missing_data  = group[0].treat_missing_data
      namespace           = group[0].namespace
      metric_name         = group[0].metric_name
      dimensions          = group[0].dimensions
      statistic           = group[0].statistic
      extended_statistic  = group[0].extended_statistic
      unit                = null
      queries = [
        for q in group[0].queries : {
          id          = q.id
          expression  = q.expression
          label       = q.label
          return_data = q.return_data
          period      = null
          metric = q.metric == null ? null : {
            namespace   = q.metric.namespace
            metric_name = q.metric.metric_name
            dimensions  = q.metric.dimensions
            stat        = q.metric.stat
            period      = group[0].cfg.period
            unit        = null
          }
        }
      ]
    }
  }

  duplicate_alarm_keys = sort(distinct(concat(
    [for key, group in local.preset_alarm_groups : key if length(group) > 1],
    tolist(setintersection(toset(keys(var.alarms)), toset(keys(local.preset_alarm_groups)))),
  )))

  all_alarm_specs = merge(local.custom_alarm_specs, local.preset_alarm_specs)
  enabled_alarms  = { for k, s in local.all_alarm_specs : k => s if s.enabled }

  provider_region  = module.naming.region
  alarm_regions    = { for k, s in local.enabled_alarms : k => coalesce(s.region, local.provider_region) }
  alarm_topic_arns = { for k, s in local.enabled_alarms : k => try([var.notifications.topic_arns[local.alarm_regions[k]][s.severity]], []) }

  alarm_full_names = { for k in keys(local.enabled_alarms) : k => "${local.base_name}-${k}" }
  alarm_names      = { for k, n in local.alarm_full_names : k => length(n) <= 255 ? n : "${trimsuffix(substr(n, 0, 248), "-")}-${substr(md5(n), 0, 6)}" }

  log_filter_full_names = { for k in keys(var.log_metric_filters) : k => "${local.base_name}-log-${k}" }
  log_filter_names      = { for k, n in local.log_filter_full_names : k => length(n) <= 512 ? n : "${trimsuffix(substr(n, 0, 505), "-")}-${substr(md5(n), 0, 6)}" }

  cis_enabled      = var.cis_cloudtrail_metric_filters.enabled
  cis_namespace    = coalesce(var.cis_cloudtrail_metric_filters.namespace, local.log_metrics_namespace)
  cis_filters      = local.cis_enabled ? local.cis_filter_catalog : {}
  cis_filter_names = { for k in keys(local.cis_filters) : k => "${local.base_name}-${k}" }

  cis_filter_catalog = {
    "cis-cloudwatch-1" = {
      control     = "CloudWatch.1"
      title       = "A log metric filter and alarm should exist for usage of the \"root\" user"
      metric_name = "RootAccountUsage"
      pattern     = "{$.userIdentity.type=\"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType !=\"AwsServiceEvent\"}"
    }
    "cis-cloudwatch-2" = {
      control     = "CloudWatch.2"
      title       = "Ensure a log metric filter and alarm exist for unauthorized API calls"
      metric_name = "UnauthorizedAPICalls"
      pattern     = "{($.errorCode=\"*UnauthorizedOperation\") || ($.errorCode=\"AccessDenied*\")}"
    }
    "cis-cloudwatch-3" = {
      control     = "CloudWatch.3"
      title       = "Ensure a log metric filter and alarm exist for Management Console sign-in without MFA"
      metric_name = "ConsoleSignInWithoutMFA"
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
    }
    "cis-cloudwatch-4" = {
      control     = "CloudWatch.4"
      title       = "Ensure a log metric filter and alarm exist for IAM policy changes"
      metric_name = "IAMPolicyChanges"
      pattern     = "{($.eventSource=iam.amazonaws.com) && (($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy))}"
    }
    "cis-cloudwatch-5" = {
      control     = "CloudWatch.5"
      title       = "Ensure a log metric filter and alarm exist for CloudTrail configuration changes"
      metric_name = "CloudTrailConfigChanges"
      pattern     = "{($.eventName=CreateTrail) || ($.eventName=UpdateTrail) || ($.eventName=DeleteTrail) || ($.eventName=StartLogging) || ($.eventName=StopLogging)}"
    }
    "cis-cloudwatch-6" = {
      control     = "CloudWatch.6"
      title       = "Ensure a log metric filter and alarm exist for AWS Management Console authentication failures"
      metric_name = "ConsoleAuthenticationFailures"
      pattern     = "{($.eventName=ConsoleLogin) && ($.errorMessage=\"Failed authentication\")}"
    }
    "cis-cloudwatch-7" = {
      control     = "CloudWatch.7"
      title       = "Ensure a log metric filter and alarm exist for disabling or scheduled deletion of customer managed keys"
      metric_name = "DisableOrDeleteCMK"
      pattern     = "{($.eventSource=kms.amazonaws.com) && (($.eventName=DisableKey) || ($.eventName=ScheduleKeyDeletion))}"
    }
    "cis-cloudwatch-8" = {
      control     = "CloudWatch.8"
      title       = "Ensure a log metric filter and alarm exist for S3 bucket policy changes"
      metric_name = "S3BucketPolicyChanges"
      pattern     = "{($.eventSource=s3.amazonaws.com) && (($.eventName=PutBucketAcl) || ($.eventName=PutBucketPolicy) || ($.eventName=PutBucketCors) || ($.eventName=PutBucketLifecycle) || ($.eventName=PutBucketReplication) || ($.eventName=DeleteBucketPolicy) || ($.eventName=DeleteBucketCors) || ($.eventName=DeleteBucketLifecycle) || ($.eventName=DeleteBucketReplication))}"
    }
    "cis-cloudwatch-9" = {
      control     = "CloudWatch.9"
      title       = "Ensure a log metric filter and alarm exist for AWS Config configuration changes"
      metric_name = "AWSConfigChanges"
      pattern     = "{($.eventSource=config.amazonaws.com) && (($.eventName=StopConfigurationRecorder) || ($.eventName=DeleteDeliveryChannel) || ($.eventName=PutDeliveryChannel) || ($.eventName=PutConfigurationRecorder))}"
    }
    "cis-cloudwatch-10" = {
      control     = "CloudWatch.10"
      title       = "Ensure a log metric filter and alarm exist for security group changes"
      metric_name = "SecurityGroupChanges"
      pattern     = "{($.eventName=AuthorizeSecurityGroupIngress) || ($.eventName=AuthorizeSecurityGroupEgress) || ($.eventName=RevokeSecurityGroupIngress) || ($.eventName=RevokeSecurityGroupEgress) || ($.eventName=CreateSecurityGroup) || ($.eventName=DeleteSecurityGroup)}"
    }
    "cis-cloudwatch-11" = {
      control     = "CloudWatch.11"
      title       = "Ensure a log metric filter and alarm exist for changes to Network Access Control Lists (NACL)"
      metric_name = "NACLChanges"
      pattern     = "{($.eventName=CreateNetworkAcl) || ($.eventName=CreateNetworkAclEntry) || ($.eventName=DeleteNetworkAcl) || ($.eventName=DeleteNetworkAclEntry) || ($.eventName=ReplaceNetworkAclEntry) || ($.eventName=ReplaceNetworkAclAssociation)}"
    }
    "cis-cloudwatch-12" = {
      control     = "CloudWatch.12"
      title       = "Ensure a log metric filter and alarm exist for changes to network gateways"
      metric_name = "NetworkGatewayChanges"
      pattern     = "{($.eventName=CreateCustomerGateway) || ($.eventName=DeleteCustomerGateway) || ($.eventName=AttachInternetGateway) || ($.eventName=CreateInternetGateway) || ($.eventName=DeleteInternetGateway) || ($.eventName=DetachInternetGateway)}"
    }
    "cis-cloudwatch-13" = {
      control     = "CloudWatch.13"
      title       = "Ensure a log metric filter and alarm exist for route table changes"
      metric_name = "RouteTableChanges"
      pattern     = "{($.eventSource=ec2.amazonaws.com) && (($.eventName=CreateRoute) || ($.eventName=CreateRouteTable) || ($.eventName=ReplaceRoute) || ($.eventName=ReplaceRouteTableAssociation) || ($.eventName=DeleteRouteTable) || ($.eventName=DeleteRoute) || ($.eventName=DisassociateRouteTable))}"
    }
    "cis-cloudwatch-14" = {
      control     = "CloudWatch.14"
      title       = "Ensure a log metric filter and alarm exist for VPC changes"
      metric_name = "VPCChanges"
      pattern     = "{($.eventName=CreateVpc) || ($.eventName=DeleteVpc) || ($.eventName=ModifyVpcAttribute) || ($.eventName=AcceptVpcPeeringConnection) || ($.eventName=CreateVpcPeeringConnection) || ($.eventName=DeleteVpcPeeringConnection) || ($.eventName=RejectVpcPeeringConnection) || ($.eventName=AttachClassicLinkVpc) || ($.eventName=DetachClassicLinkVpc) || ($.eventName=DisableVpcClassicLink) || ($.eventName=EnableVpcClassicLink)}"
    }

  }
}
