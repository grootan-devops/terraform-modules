locals {
  managed_rules = {
    "access-keys-rotated" = {
      identifier                  = "ACCESS_KEYS_ROTATED"
      description                 = "IAM.3: Checks if active IAM access keys are rotated (changed) within the number of days specified in maxAccessKeyAge."
      controls                    = ["IAM.3"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = { maxAccessKeyAge = "90" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "account-part-of-organizations" = {
      identifier                  = "ACCOUNT_PART_OF_ORGANIZATIONS"
      description                 = "Account.2: Rule checks whether AWS account is part of AWS Organizations."
      controls                    = ["Account.2"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1"]
    }
    "alb-desync-mode-check" = {
      identifier                  = "ALB_DESYNC_MODE_CHECK"
      description                 = "ELB.12: Checks if an Application Load Balancer (ALB) is configured with a user defined desync mitigation mode."
      controls                    = ["ELB.12"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { desyncMode = "defensive,strictest" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = []
    }
    "alb-http-drop-invalid-header-enabled" = {
      identifier                  = "ALB_HTTP_DROP_INVALID_HEADER_ENABLED"
      description                 = "ELB.4: Checks if rule evaluates AWS Application Load Balancers (ALB) to ensure they are configured to drop http headers."
      controls                    = ["ELB.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = []
    }
    "alb-http-to-https-redirection-check" = {
      identifier                  = "ALB_HTTP_TO_HTTPS_REDIRECTION_CHECK"
      description                 = "ELB.1: Checks if HTTP to HTTPS redirection is configured on all HTTP listeners of Application Load Balancers."
      controls                    = ["ELB.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "alb-waf-enabled" = {
      identifier                  = "ALB_WAF_ENABLED"
      description                 = "ELB.16: Checks if Web Application Firewall (WAF) is enabled on Application Load Balancers (ALBs)."
      controls                    = ["ELB.16"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = []
    }
    "amplify-app-tagged" = {
      identifier                  = "AMPLIFY_APP_TAGGED"
      description                 = "Amplify.1: Checks if AWS Amplify apps have tags."
      controls                    = ["Amplify.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Amplify::App"]
      only_regions                = []
      except_regions              = ["af-south-1", "ap-east-2", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "amplify-branch-tagged" = {
      identifier                  = "AMPLIFY_BRANCH_TAGGED"
      description                 = "Amplify.2: Checks if AWS Amplify branches have tags."
      controls                    = ["Amplify.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Amplify::Branch"]
      only_regions                = []
      except_regions              = ["af-south-1", "ap-east-2", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "api-gw-associated-with-waf" = {
      identifier                  = "API_GW_ASSOCIATED_WITH_WAF"
      description                 = "APIGateway.4: Checks if an Amazon API Gateway API stage is using an AWS WAF web access control list (web ACL)."
      controls                    = ["APIGateway.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ApiGateway::Stage"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6"]
    }
    "api-gw-execution-logging-enabled" = {
      identifier                  = "API_GW_EXECUTION_LOGGING_ENABLED"
      description                 = "APIGateway.1: Checks if all methods in Amazon API Gateway stages have logging enabled."
      controls                    = ["APIGateway.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ApiGateway::Stage", "AWS::ApiGatewayV2::Stage"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6"]
    }
    "api-gw-ssl-enabled" = {
      identifier                  = "API_GW_SSL_ENABLED"
      description                 = "APIGateway.2: Checks if a REST API stage uses an SSL certificate."
      controls                    = ["APIGateway.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ApiGateway::Stage"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6"]
    }
    "api-gw-xray-enabled" = {
      identifier                  = "API_GW_XRAY_ENABLED"
      description                 = "APIGateway.3: Checks if AWS X-Ray tracing is enabled on Amazon API Gateway REST APIs."
      controls                    = ["APIGateway.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ApiGateway::Stage"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6"]
    }
    "autoscaling-group-elb-healthcheck-required" = {
      identifier                  = "AUTOSCALING_GROUP_ELB_HEALTHCHECK_REQUIRED"
      description                 = "AutoScaling.1: Checks if your Amazon EC2 Auto Scaling groups that are associated with an Elastic Load Balancer use Elastic Load Balancing health checks."
      controls                    = ["AutoScaling.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::AutoScaling::AutoScalingGroup"]
      only_regions                = []
      except_regions              = []
    }
    "autoscaling-launch-template" = {
      identifier                  = "AUTOSCALING_LAUNCH_TEMPLATE"
      description                 = "AutoScaling.9: Checks if an Amazon Elastic Compute Cloud (EC2) Auto Scaling group is created from an EC2 launch template."
      controls                    = ["AutoScaling.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::AutoScaling::AutoScalingGroup"]
      only_regions                = []
      except_regions              = ["mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "autoscaling-multiple-az" = {
      identifier                  = "AUTOSCALING_MULTIPLE_AZ"
      description                 = "AutoScaling.2: Checks if the Auto Scaling group spans multiple Availability Zones."
      controls                    = ["AutoScaling.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::AutoScaling::AutoScalingGroup"]
      only_regions                = []
      except_regions              = ["ca-west-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "autoscaling-multiple-instance-types" = {
      identifier                  = "AUTOSCALING_MULTIPLE_INSTANCE_TYPES"
      description                 = "AutoScaling.6: Checks if an Amazon EC2 Auto Scaling group uses multiple instance types."
      controls                    = ["AutoScaling.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::AutoScaling::AutoScalingGroup"]
      only_regions                = []
      except_regions              = []
    }
    "backup-recovery-point-encrypted" = {
      identifier                  = "BACKUP_RECOVERY_POINT_ENCRYPTED"
      description                 = "Backup.1: Checks if a recovery point is encrypted."
      controls                    = ["Backup.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Backup::RecoveryPoint"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1"]
    }
    "batch-compute-environment-tagged" = {
      identifier                  = "BATCH_COMPUTE_ENVIRONMENT_TAGGED"
      description                 = "Batch.3: Checks if AWS Batch compute environments have tags."
      controls                    = ["Batch.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Batch::ComputeEnvironment"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "batch-job-queue-tagged" = {
      identifier                  = "BATCH_JOB_QUEUE_TAGGED"
      description                 = "Batch.1: Checks if AWS Batch job queues have tags."
      controls                    = ["Batch.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Batch::JobQueue"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "batch-managed-compute-env-compute-resources-tagged" = {
      identifier                  = "BATCH_MANAGED_COMPUTE_ENV_COMPUTE_RESOURCES_TAGGED"
      description                 = "Batch.4: Checks if AWS Batch managed compute environments compute resources have tags."
      controls                    = ["Batch.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Batch::ComputeEnvironment"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "batch-scheduling-policy-tagged" = {
      identifier                  = "BATCH_SCHEDULING_POLICY_TAGGED"
      description                 = "Batch.2: Checks if AWS Batch scheduling policies have tags."
      controls                    = ["Batch.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Batch::SchedulingPolicy"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "cloud-trail-cloud-watch-logs-enabled" = {
      identifier                  = "CLOUD_TRAIL_CLOUD_WATCH_LOGS_ENABLED"
      description                 = "CloudTrail.5: Checks if AWS CloudTrail trails are configured to send logs to CloudWatch logs."
      controls                    = ["CloudTrail.5"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloud-trail-encryption-enabled" = {
      identifier                  = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
      description                 = "CloudTrail.2: Checks if AWS CloudTrail is configured to use the server side encryption (SSE) AWS Key Management Service (AWS KMS) encryption."
      controls                    = ["CloudTrail.2"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloud-trail-log-file-validation-enabled" = {
      identifier                  = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
      description                 = "CloudTrail.4: Checks if AWS CloudTrail creates a signed digest file with logs."
      controls                    = ["CloudTrail.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloudfront-accesslogs-enabled" = {
      identifier                  = "CLOUDFRONT_ACCESSLOGS_ENABLED"
      description                 = "CloudFront.5: Checks if Amazon CloudFront distributions are configured to deliver access logs to an Amazon S3 bucket using standard logging (legacy)."
      controls                    = ["CloudFront.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-associated-with-waf" = {
      identifier                  = "CLOUDFRONT_ASSOCIATED_WITH_WAF"
      description                 = "CloudFront.6: Checks if Amazon CloudFront distributions are associated with either web application firewall (WAF) or WAFv2 web access control lists (ACLs)."
      controls                    = ["CloudFront.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-custom-ssl-certificate" = {
      identifier                  = "CLOUDFRONT_CUSTOM_SSL_CERTIFICATE"
      description                 = "CloudFront.7: Checks if the certificate associated with an Amazon CloudFront distribution is the default SSL certificate."
      controls                    = ["CloudFront.7"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-default-root-object-configured" = {
      identifier                  = "CLOUDFRONT_DEFAULT_ROOT_OBJECT_CONFIGURED"
      description                 = "CloudFront.1: Checks if an Amazon CloudFront distribution is configured to return a specific object that is the default root object."
      controls                    = ["CloudFront.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-distribution-key-group-enabled" = {
      identifier                  = "CLOUDFRONT_DISTRIBUTION_KEY_GROUP_ENABLED"
      description                 = "CloudFront.17: Checks whether Amazon CloudFront distributions use only trusted key groups for signed URL or signed cookie authentication for all cache behaviors."
      controls                    = ["CloudFront.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-no-deprecated-ssl-protocols" = {
      identifier                  = "CLOUDFRONT_NO_DEPRECATED_SSL_PROTOCOLS"
      description                 = "CloudFront.10: Checks if CloudFront distributions are using deprecated SSL protocols for HTTPS communication between CloudFront edge locations and custom origins."
      controls                    = ["CloudFront.10"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-origin-failover-enabled" = {
      identifier                  = "CLOUDFRONT_ORIGIN_FAILOVER_ENABLED"
      description                 = "CloudFront.4: Checks if an origin group is configured for the distribution of at least two origins in the origin group for Amazon CloudFront."
      controls                    = ["CloudFront.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-origin-lambda-url-oac-enabled" = {
      identifier                  = "CLOUDFRONT_ORIGIN_LAMBDA_URL_OAC_ENABLED"
      description                 = "CloudFront.16: Checks if Amazon CloudFront distributions with Amazon Lambda Function URL origins have origin access control (OAC) enabled."
      controls                    = ["CloudFront.16"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-s3-origin-access-control-enabled" = {
      identifier                  = "CLOUDFRONT_S3_ORIGIN_ACCESS_CONTROL_ENABLED"
      description                 = "CloudFront.13: Checks if an Amazon CloudFront distribution with an Amazon Simple Storage Service (Amazon S3) Origin type has origin access control (OAC) enabled."
      controls                    = ["CloudFront.13"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-s3-origin-non-existent-bucket" = {
      identifier                  = "CLOUDFRONT_S3_ORIGIN_NON_EXISTENT_BUCKET"
      description                 = "CloudFront.12: Checks if Amazon CloudFront distributions point to a non-existent S3 bucket."
      controls                    = ["CloudFront.12"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = ["ap-east-2", "ap-southeast-3", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "cn-north-1", "il-central-1", "us-east-1"]
      except_regions              = []
    }
    "cloudfront-sni-enabled" = {
      identifier                  = "CLOUDFRONT_SNI_ENABLED"
      description                 = "CloudFront.8: Checks if Amazon CloudFront distributions are using a custom SSL certificate and are configured to use SNI to serve HTTPS requests."
      controls                    = ["CloudFront.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-ssl-policy-check" = {
      identifier                  = "CLOUDFRONT_SSL_POLICY_CHECK"
      description                 = "CloudFront.15: Checks if Amazon CloudFront distributions are configured with the specified security policies.The rule is NON_COMPLIANT if a CloudFront Distribution is not configured with security policies that you specify."
      controls                    = ["CloudFront.15"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { securityPolicies = "TLSv1.2_2025,TLSv1.3_2025" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-traffic-to-origin-encrypted" = {
      identifier                  = "CLOUDFRONT_TRAFFIC_TO_ORIGIN_ENCRYPTED"
      description                 = "CloudFront.9: Checks if Amazon CloudFront distributions are encrypting traffic to custom origins."
      controls                    = ["CloudFront.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudfront-viewer-policy-https" = {
      identifier                  = "CLOUDFRONT_VIEWER_POLICY_HTTPS"
      description                 = "CloudFront.3: Checks whether your Amazon CloudFront distributions use HTTPS (directly or via a redirection)."
      controls                    = ["CloudFront.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudFront::Distribution"]
      only_regions                = ["us-east-1"]
      except_regions              = []
    }
    "cloudtrail-all-read-s3-data-event-check" = {
      identifier                  = "CLOUDTRAIL_ALL_READ_S3_DATA_EVENT_CHECK"
      description                 = "S3.23: Checks if an AWS CloudTrail multi-Region trail is enabled and logs all read S3 data events for your buckets."
      controls                    = ["S3.23"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloudtrail-all-write-s3-data-event-check" = {
      identifier                  = "CLOUDTRAIL_ALL_WRITE_S3_DATA_EVENT_CHECK"
      description                 = "S3.22: Checks if an AWS CloudTrail multi-Region trail is enabled and logs all write S3 data events for your buckets."
      controls                    = ["S3.22"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloudtrail-enabled" = {
      identifier                  = "CLOUD_TRAIL_ENABLED"
      description                 = "CloudTrail.3: Checks if an AWS CloudTrail trail is enabled in your AWS account."
      controls                    = ["CloudTrail.3"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cloudwatch-alarm-action-check" = {
      identifier                  = "CLOUDWATCH_ALARM_ACTION_CHECK"
      description                 = "CloudWatch.15: Checks if CloudWatch alarms have an action configured for the ALARM, INSUFFICIENT_DATA, or OK state."
      controls                    = ["CloudWatch.15"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { alarmActionRequired = "true", insufficientDataActionRequired = "false", okActionRequired = "false" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudWatch::Alarm"]
      only_regions                = []
      except_regions              = []
    }
    "cloudwatch-alarm-action-enabled-check" = {
      identifier                  = "CLOUDWATCH_ALARM_ACTION_ENABLED_CHECK"
      description                 = "CloudWatch.17: Checks if Amazon CloudWatch alarms actions are in enabled state."
      controls                    = ["CloudWatch.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::CloudWatch::Alarm"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "cloudwatch-log-group-encrypted" = {
      identifier                  = "CLOUDWATCH_LOG_GROUP_ENCRYPTED"
      description                 = "Library baseline: Checks if Amazon CloudWatch Log Groups are encrypted with any AWS KMS key or a specified AWS KMS key Id."
      controls                    = []
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cmk-backing-key-rotation-enabled" = {
      identifier                  = "CMK_BACKING_KEY_ROTATION_ENABLED"
      description                 = "KMS.4: Checks if automatic key rotation is enabled for each key and matches to the key ID of the customer created AWS KMS key."
      controls                    = ["KMS.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "cognito-user-pool-deletion-protection-enabled" = {
      identifier                  = "COGNITO_USER_POOL_DELETION_PROTECTION_ENABLED"
      description                 = "Cognito.6: Checks whether Amazon Cognito user pools has deletion protection enabled."
      controls                    = ["Cognito.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Cognito::UserPool"]
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "cognito-user-pool-mfa-enabled" = {
      identifier                  = "COGNITO_USER_POOL_MFA_ENABLED"
      description                 = "Cognito.5: Checks if Amazon Cognito user pools configured with a PASSWORD-only sign-in policy have Multi-Factor Authentication (MFA) enabled."
      controls                    = ["Cognito.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Cognito::UserPool"]
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "cognito-user-pool-password-policy-check" = {
      identifier                  = "COGNITO_USER_POOL_PASSWORD_POLICY_CHECK"
      description                 = "Cognito.3: Checks if the password policy for Amazon cognito user pool meets the specified requirements indicated in the parameters."
      controls                    = ["Cognito.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { minLength = "14" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Cognito::UserPool"]
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "cognito-userpool-cust-auth-threat-full-check" = {
      identifier                  = "COGNITO_USERPOOL_CUST_AUTH_THREAT_FULL_CHECK"
      description                 = "Cognito.4: Checks if Amazon Cognito user pools have threat protection enabled with full-function enforcement mode for custom authentication."
      controls                    = ["Cognito.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Cognito::UserPool"]
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "custom-eventbus-policy-attached" = {
      identifier                  = "CUSTOM_EVENTBUS_POLICY_ATTACHED"
      description                 = "EventBridge.3: Checks if Amazon EventBridge custom event buses have a resource-based policy attached."
      controls                    = ["EventBridge.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Events::EventBus"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "cw-loggroup-retention-period-check" = {
      identifier                  = "CW_LOGGROUP_RETENTION_PERIOD_CHECK"
      description                 = "CloudWatch.16: Checks if an Amazon CloudWatch LogGroup retention period is set to greater than 365 days or else a specified retention period."
      controls                    = ["CloudWatch.16"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { MinRetentionTime = "365" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "db-instance-backup-enabled" = {
      identifier                  = "DB_INSTANCE_BACKUP_ENABLED"
      description                 = "RDS.11: Checks if RDS DB instances have backups enabled."
      controls                    = ["RDS.11"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { backupRetentionMinimum = "7" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "dynamodb-autoscaling-enabled" = {
      identifier                  = "DYNAMODB_AUTOSCALING_ENABLED"
      description                 = "DynamoDB.1: Checks if Amazon DynamoDB tables or global secondary indexes can process read/write capacity using on-demand mode or provisioned mode with auto scaling enabled."
      controls                    = ["DynamoDB.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "dynamodb-pitr-enabled" = {
      identifier                  = "DYNAMODB_PITR_ENABLED"
      description                 = "DynamoDB.2: Checks if point-in-time recovery (PITR) is enabled for Amazon DynamoDB tables."
      controls                    = ["DynamoDB.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::DynamoDB::Table"]
      only_regions                = []
      except_regions              = []
    }
    "dynamodb-resources-protected-by-backup-plan" = {
      identifier                  = "DYNAMODB_RESOURCES_PROTECTED_BY_BACKUP_PLAN"
      description                 = "DynamoDB.4: Checks if Amazon DynamoDB tables are protected by a backup plan."
      controls                    = ["DynamoDB.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1"]
    }
    "dynamodb-table-deletion-protection-enabled" = {
      identifier                  = "DYNAMODB_TABLE_DELETION_PROTECTION_ENABLED"
      description                 = "DynamoDB.6: Checks if an Amazon DynamoDB table have deletion protection set to enabled."
      controls                    = ["DynamoDB.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::DynamoDB::Table"]
      only_regions                = []
      except_regions              = []
    }
    "dynamodb-table-encrypted-kms" = {
      identifier                  = "DYNAMODB_TABLE_ENCRYPTED_KMS"
      description                 = "Library baseline: Checks if Amazon DynamoDB table is encrypted with AWS Key Management Service (KMS)."
      controls                    = []
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::DynamoDB::Table"]
      only_regions                = []
      except_regions              = []
    }
    "ebs-resources-protected-by-backup-plan" = {
      identifier                  = "EBS_RESOURCES_PROTECTED_BY_BACKUP_PLAN"
      description                 = "EC2.28: Checks if Amazon Elastic Block Store (Amazon EBS) volumes are protected by a backup plan."
      controls                    = ["EC2.28"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1"]
    }
    "ebs-snapshot-public-restorable-check" = {
      identifier                  = "EBS_SNAPSHOT_PUBLIC_RESTORABLE_CHECK"
      description                 = "EC2.1: Checks if Amazon Elastic Block Store (Amazon EBS) snapshots are not publicly restorable."
      controls                    = ["EC2.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["eu-south-2"]
    }
    "ec2-dhcp-options-tagged" = {
      identifier                  = "EC2_DHCP_OPTIONS_TAGGED"
      description                 = "EC2.174: Checks if Amazon EC2 DHCP options have tags."
      controls                    = ["EC2.174"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::DHCPOptions"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ec2-ebs-encryption-by-default" = {
      identifier                  = "EC2_EBS_ENCRYPTION_BY_DEFAULT"
      description                 = "EC2.7: Checks if Amazon Elastic Block Store (EBS) encryption is enabled by default."
      controls                    = ["EC2.7"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "ec2-imdsv2-check" = {
      identifier                  = "EC2_IMDSV2_CHECK"
      description                 = "EC2.8: Checks whether your Amazon Elastic Compute Cloud (Amazon EC2) instance metadata version is configured with Instance Metadata Service Version 2 (IMDSv2)."
      controls                    = ["EC2.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Instance"]
      only_regions                = []
      except_regions              = []
    }
    "ec2-instance-multiple-eni-check" = {
      identifier                  = "EC2_INSTANCE_MULTIPLE_ENI_CHECK"
      description                 = "EC2.17: Checks if Amazon Elastic Compute Cloud (Amazon EC2) uses multiple Elastic Network Interfaces (ENIs) or Elastic Fabric Adapters (EFAs)."
      controls                    = ["EC2.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Instance"]
      only_regions                = []
      except_regions              = []
    }
    "ec2-instance-no-public-ip" = {
      identifier                  = "EC2_INSTANCE_NO_PUBLIC_IP"
      description                 = "EC2.9: Checks whether Amazon Elastic Compute Cloud (Amazon EC2) instances have a public IP association."
      controls                    = ["EC2.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Instance"]
      only_regions                = []
      except_regions              = []
    }
    "ec2-launch-template-imdsv2-check" = {
      identifier                  = "EC2_LAUNCH_TEMPLATE_IMDSV2_CHECK"
      description                 = "EC2.170: Checks if the currently set default version of an Amazon EC2 Launch Template requires new launched instances to use V2 of the Amazon EC2 Instance Metadata Service (IMDSv2)."
      controls                    = ["EC2.170"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::LaunchTemplate"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ec2-launch-template-public-ip-disabled" = {
      identifier                  = "EC2_LAUNCH_TEMPLATE_PUBLIC_IP_DISABLED"
      description                 = "EC2.25: Checks if Amazon EC2 Launch Templates are set to assign public IP addresses to Network Interfaces."
      controls                    = ["EC2.25"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::LaunchTemplate"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ec2-launch-template-tagged" = {
      identifier                  = "EC2_LAUNCH_TEMPLATE_TAGGED"
      description                 = "EC2.175: Checks if Amazon EC2 launch templates have tags."
      controls                    = ["EC2.175"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::LaunchTemplate"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ec2-launch-templates-ebs-volume-encrypted" = {
      identifier                  = "EC2_LAUNCH_TEMPLATES_EBS_VOLUME_ENCRYPTED"
      description                 = "EC2.181: Checks whether Amazon EC2 launch templates have encryption enabled for all attached EBS volumes.The rule is NON_COMPLIANT if encryption is set to False for any EBS volume configured in the launch template."
      controls                    = ["EC2.181"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::LaunchTemplate"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "mx-central-1"]
    }
    "ec2-managedinstance-association-compliance-status-check" = {
      identifier                  = "EC2_MANAGEDINSTANCE_ASSOCIATION_COMPLIANCE_STATUS_CHECK"
      description                 = "SSM.3: Checks if the status of the AWS Systems Manager association compliance is COMPLIANT or NON_COMPLIANT after the association execution on the instance."
      controls                    = ["SSM.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SSM::AssociationCompliance"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-northeast-3", "ap-southeast-6", "ap-southeast-7", "mx-central-1"]
    }
    "ec2-managedinstance-patch-compliance-status-check" = {
      identifier                  = "EC2_MANAGEDINSTANCE_PATCH_COMPLIANCE_STATUS_CHECK"
      description                 = "SSM.2: Checks if the compliance status of the AWS Systems Manager patch compliance is COMPLIANT or NON_COMPLIANT after the patch installation on the instance."
      controls                    = ["SSM.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SSM::PatchCompliance"]
      only_regions                = []
      except_regions              = ["ap-northeast-3", "eu-south-1"]
    }
    "ec2-paravirtual-instance-check" = {
      identifier                  = "EC2_PARAVIRTUAL_INSTANCE_CHECK"
      description                 = "EC2.24: Checks if the virtualization type of an EC2 instance is paravirtual."
      controls                    = ["EC2.24"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Instance"]
      only_regions                = ["ap-northeast-1", "ap-southeast-1", "ap-southeast-2", "cn-north-1", "eu-central-1", "eu-west-1", "sa-east-1", "us-east-1", "us-west-1", "us-west-2"]
      except_regions              = []
    }
    "ec2-security-group-attached-to-eni-periodic" = {
      identifier                  = "EC2_SECURITY_GROUP_ATTACHED_TO_ENI_PERIODIC"
      description                 = "EC2.22: Checks if non-default security groups are attached to Elastic network interfaces (ENIs)."
      controls                    = ["EC2.22"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-northeast-3", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ecs-container-insights-enabled" = {
      identifier                  = "ECS_CONTAINER_INSIGHTS_ENABLED"
      description                 = "ECS.12: Checks if Amazon Elastic Container Service clusters have container insights enabled."
      controls                    = ["ECS.12"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::Cluster"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-containers-nonprivileged" = {
      identifier                  = "ECS_CONTAINERS_NONPRIVILEGED"
      description                 = "ECS.4: Checks if the privileged parameter in the container definition of ECSTaskDefinitions is set to 'true'."
      controls                    = ["ECS.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-containers-readonly-access" = {
      identifier                  = "ECS_CONTAINERS_READONLY_ACCESS"
      description                 = "ECS.5: Checks if Amazon Elastic Container Service (Amazon ECS) Containers only have read-only access to its root filesystems."
      controls                    = ["ECS.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-fargate-latest-platform-version" = {
      identifier                  = "ECS_FARGATE_LATEST_PLATFORM_VERSION"
      description                 = "ECS.10: Checks if ECS Fargate services is set to the latest platform version."
      controls                    = ["ECS.10"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { latestLinuxVersion = "1.4.0", latestWindowsVersion = "1.0.0" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::Service"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-no-environment-secrets" = {
      identifier                  = "ECS_NO_ENVIRONMENT_SECRETS"
      description                 = "ECS.8: Checks if secrets are passed as container environment variables."
      controls                    = ["ECS.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { secretKeys = "AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,ECS_ENGINE_AUTH_DATA" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "ecs-task-definition-efs-encryption-enabled" = {
      identifier                  = "ECS_TASK_DEFINITION_EFS_ENCRYPTION_ENABLED"
      description                 = "ECS.18: Checks if Amazon ECS Task Definitions with EFS volumes have in-transit encryption enabled."
      controls                    = ["ECS.18"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-task-definition-linux-user-non-root" = {
      identifier                  = "ECS_TASK_DEFINITION_LINUX_USER_NON_ROOT"
      description                 = "ECS.20: Checks if the latest active revision of an Amazon ECS task definition configures Linux containers to run as non-root users.The rule is NON_COMPLIANT if root user is specified or user configuration is absent for any container."
      controls                    = ["ECS.20"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-task-definition-log-configuration" = {
      identifier                  = "ECS_TASK_DEFINITION_LOG_CONFIGURATION"
      description                 = "ECS.9: Checks if logConfiguration is set on active ECS Task Definitions."
      controls                    = ["ECS.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "ecs-task-definition-network-mode-not-host" = {
      identifier                  = "ECS_TASK_DEFINITION_NETWORK_MODE_NOT_HOST"
      description                 = "ECS.17: Checks if the latest active revision of Amazon ECS task definitions use host network mode."
      controls                    = ["ECS.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "ecs-task-definition-pid-mode-check" = {
      identifier                  = "ECS_TASK_DEFINITION_PID_MODE_CHECK"
      description                 = "ECS.3: Checks if ECSTaskDefinitions are configured to share a host's process namespace with its Amazon Elastic Container Service (Amazon ECS) containers."
      controls                    = ["ECS.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "ecs-task-definition-windows-user-non-admin" = {
      identifier                  = "ECS_TASK_DEFINITION_WINDOWS_USER_NON_ADMIN"
      description                 = "ECS.21: Checks if the latest active revision of an Amazon ECS task definition configures Windows containers to run as non-administrator users."
      controls                    = ["ECS.21"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ECS::TaskDefinition"]
      only_regions                = []
      except_regions              = []
    }
    "efs-access-point-enforce-root-directory" = {
      identifier                  = "EFS_ACCESS_POINT_ENFORCE_ROOT_DIRECTORY"
      description                 = "EFS.3: Checks if Amazon Elastic File System (Amazon EFS) access points are configured to enforce a root directory."
      controls                    = ["EFS.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EFS::AccessPoint"]
      only_regions                = []
      except_regions              = ["cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "efs-access-point-enforce-user-identity" = {
      identifier                  = "EFS_ACCESS_POINT_ENFORCE_USER_IDENTITY"
      description                 = "EFS.4: Checks if Amazon Elastic File System (Amazon EFS) access points are configured to enforce a user identity."
      controls                    = ["EFS.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EFS::AccessPoint"]
      only_regions                = []
      except_regions              = ["cn-northwest-1"]
    }
    "efs-automatic-backups-enabled" = {
      identifier                  = "EFS_AUTOMATIC_BACKUPS_ENABLED"
      description                 = "EFS.7: Checks if an Amazon Elastic File System (Amazon EFS) file system has automatic backups enabled."
      controls                    = ["EFS.7"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EFS::FileSystem"]
      only_regions                = []
      except_regions              = []
    }
    "efs-encrypted-check" = {
      identifier                  = "EFS_ENCRYPTED_CHECK"
      description                 = "EFS.1: Checks if Amazon Elastic File System (Amazon EFS) is configured to encrypt the file data using AWS Key Management Service (AWS KMS)."
      controls                    = ["EFS.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "efs-filesystem-ct-encrypted" = {
      identifier                  = "EFS_FILESYSTEM_CT_ENCRYPTED"
      description                 = "EFS.8: Checks if Amazon Elastic File System (Amazon EFS) encrypts data with AWS Key Management Service (AWS KMS)."
      controls                    = ["EFS.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EFS::FileSystem"]
      only_regions                = []
      except_regions              = ["ca-west-1"]
    }
    "efs-in-backup-plan" = {
      identifier                  = "EFS_IN_BACKUP_PLAN"
      description                 = "EFS.2: Checks if Amazon Elastic File System (Amazon EFS) file systems are added in the backup plans of AWS Backup."
      controls                    = ["EFS.2"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "efs-mount-target-public-accessible" = {
      identifier                  = "EFS_MOUNT_TARGET_PUBLIC_ACCESSIBLE"
      description                 = "EFS.6: Checks if an Amazon Elastic File System (Amazon EFS) is associated with subnets that assign public IP addresses on launch."
      controls                    = ["EFS.6"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1"]
    }
    "eip-attached" = {
      identifier                  = "EIP_ATTACHED"
      description                 = "EC2.12: Checks whether Elastic IP addresses allocated to your account are in use."
      controls                    = ["EC2.12"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::EIP"]
      only_regions                = []
      except_regions              = []
    }
    "eks-cluster-log-enabled" = {
      identifier                  = "EKS_CLUSTER_LOG_ENABLED"
      description                 = "EKS.8: Checks if an Amazon Elastic Kubernetes Service (Amazon EKS) cluster is configured with logging enabled."
      controls                    = ["EKS.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { logTypes = "audit" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EKS::Cluster"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "il-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "eks-cluster-supported-version" = {
      identifier                  = "EKS_CLUSTER_SUPPORTED_VERSION"
      description                 = "EKS.2: Checks if an Amazon Elastic Kubernetes Service (EKS) cluster is running a supported Kubernetes version."
      controls                    = ["EKS.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { oldestVersionSupported = "1.34" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EKS::Cluster"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "il-central-1", "mx-central-1"]
    }
    "eks-endpoint-no-public-access" = {
      identifier                  = "EKS_ENDPOINT_NO_PUBLIC_ACCESS"
      description                 = "EKS.1: Checks if the Amazon Elastic Kubernetes Service (Amazon EKS) endpoint is not publicly accessible."
      controls                    = ["EKS.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "eks-nodegroup-supported-version-check" = {
      identifier                  = "EKS_NODEGROUP_SUPPORTED_VERSION_CHECK"
      description                 = "EKS.9: Checks if an Amazon Elastic Kubernetes Service (EKS) nodegroup is running the oldest supported version."
      controls                    = ["EKS.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { oldestVersionSupported = "1.34" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EKS::Nodegroup"]
      only_regions                = []
      except_regions              = ["me-central-1", "me-south-1"]
    }
    "elasticache-auto-minor-version-upgrade-check" = {
      identifier                  = "ELASTICACHE_AUTO_MINOR_VERSION_UPGRADE_CHECK"
      description                 = "ElastiCache.2: Checks if Amazon ElastiCache clusters have auto minor version upgrades enabled."
      controls                    = ["ElastiCache.2"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-4", "ca-west-1", "me-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elasticache-redis-cluster-automatic-backup-check" = {
      identifier                  = "ELASTICACHE_REDIS_CLUSTER_AUTOMATIC_BACKUP_CHECK"
      description                 = "ElastiCache.1: Check if the Amazon ElastiCache Redis clusters have automatic backup turned on."
      controls                    = ["ElastiCache.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { snapshotRetentionPeriod = "7" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2"]
    }
    "elasticache-repl-grp-auto-failover-enabled" = {
      identifier                  = "ELASTICACHE_REPL_GRP_AUTO_FAILOVER_ENABLED"
      description                 = "ElastiCache.3: Checks if Amazon ElastiCache Redis replication groups have automatic failover enabled."
      controls                    = ["ElastiCache.3"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elasticache-repl-grp-encrypted-at-rest" = {
      identifier                  = "ELASTICACHE_REPL_GRP_ENCRYPTED_AT_REST"
      description                 = "ElastiCache.4: Checks if Amazon ElastiCache replication groups have encryption-at-rest enabled."
      controls                    = ["ElastiCache.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-4", "ap-southeast-5", "ap-southeast-7", "ca-west-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elasticache-repl-grp-encrypted-in-transit" = {
      identifier                  = "ELASTICACHE_REPL_GRP_ENCRYPTED_IN_TRANSIT"
      description                 = "ElastiCache.5: Checks if Amazon ElastiCache replication groups have encryption-in-transit enabled."
      controls                    = ["ElastiCache.5"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-4", "ap-southeast-5", "ap-southeast-7", "ca-west-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elasticache-repl-grp-redis-auth-enabled" = {
      identifier                  = "ELASTICACHE_REPL_GRP_REDIS_AUTH_ENABLED"
      description                 = "ElastiCache.6: Checks if Amazon ElastiCache replication groups have Redis AUTH enabled."
      controls                    = ["ElastiCache.6"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-3", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elasticache-subnet-group-check" = {
      identifier                  = "ELASTICACHE_SUBNET_GROUP_CHECK"
      description                 = "ElastiCache.7: Checks if Amazon ElastiCache clusters are configured with a custom subnet group."
      controls                    = ["ElastiCache.7"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-northeast-3", "ap-south-2", "ap-southeast-4", "ap-southeast-6", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elb-deletion-protection-enabled" = {
      identifier                  = "ELB_DELETION_PROTECTION_ENABLED"
      description                 = "ELB.6: Checks whether an Elastic Load Balancer has deletion protection enabled."
      controls                    = ["ELB.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = []
    }
    "elb-logging-enabled" = {
      identifier                  = "ELB_LOGGING_ENABLED"
      description                 = "ELB.5: Checks if the Application Load Balancer and the Classic Load Balancer have logging enabled."
      controls                    = ["ELB.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancing::LoadBalancer", "AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = []
    }
    "elbv2-listener-encryption-in-transit" = {
      identifier                  = "ELBV2_LISTENER_ENCRYPTION_IN_TRANSIT"
      description                 = "ELB.18: Checks if listeners for the load balancers are configured with HTTPS or TLS termination."
      controls                    = ["ELB.18"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::Listener"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1"]
    }
    "elbv2-multiple-az" = {
      identifier                  = "ELBV2_MULTIPLE_AZ"
      description                 = "ELB.13: Checks if an Elastic Load Balancer V2 (Application, Network, or Gateway Load Balancer) is mapped to multiple Availability Zones (AZs)."
      controls                    = ["ELB.13"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::LoadBalancer"]
      only_regions                = []
      except_regions              = ["us-gov-east-1", "us-gov-west-1"]
    }
    "elbv2-predefined-security-policy-ssl-check" = {
      identifier                  = "ELBV2_PREDEFINED_SECURITY_POLICY_SSL_CHECK"
      description                 = "ELB.17: Checks if listeners for Application Load Balancers (ALBs) or Network Load Balancers (NLBs) use certain security policies."
      controls                    = ["ELB.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { sslPolicies = "ELBSecurityPolicy-TLS13-1-3-2021-06,ELBSecurityPolicy-TLS13-1-3-FIPS-2023-04,ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-RFC9151-FIPS-2023-07,ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP1-FIPS-2023-07,ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP2-FIPS-2023-07,ELBSecurityPolicy-TLS13-1-3-RFC9151-FIPS-2023-07,ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09,ELBSecurityPolicy-TLS13-1-2-PQ-2025-09" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::Listener"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1"]
    }
    "elbv2-targetgroup-healthcheck-protocol-encrypted" = {
      identifier                  = "ELBV2_TARGETGROUP_HEALTHCHECK_PROTOCOL_ENCRYPTED"
      description                 = "ELB.21: Checks the target groups for load balancers healthchecks use an encrypted transport protocol."
      controls                    = ["ELB.21"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::TargetGroup"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "elbv2-targetgroup-protocol-encrypted" = {
      identifier                  = "ELBV2_TARGETGROUP_PROTOCOL_ENCRYPTED"
      description                 = "ELB.22: Checks the target groups for application and network load balancers use an encrypted transport protocol."
      controls                    = ["ELB.22"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ElasticLoadBalancingV2::TargetGroup"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "encrypted-volumes" = {
      identifier                  = "ENCRYPTED_VOLUMES"
      description                 = "EC2.3: Checks if attached Amazon EBS volumes are encrypted and optionally are encrypted with a specified KMS key."
      controls                    = ["EC2.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Volume"]
      only_regions                = []
      except_regions              = []
    }
    "guardduty-ec2-protection-runtime-enabled" = {
      identifier                  = "GUARDDUTY_EC2_PROTECTION_RUNTIME_ENABLED"
      description                 = "GuardDuty.13: Checks if EC2 Runtime Monitoring with automated agent management is enabled for Amazon GuardDuty detector."
      controls                    = ["GuardDuty.13"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ca-west-1", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-ecs-protection-runtime-enabled" = {
      identifier                  = "GUARDDUTY_ECS_PROTECTION_RUNTIME_ENABLED"
      description                 = "GuardDuty.12: Checks if ECS Runtime Monitoring with automated agent management is enabled for Amazon GuardDuty detector."
      controls                    = ["GuardDuty.12"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ca-west-1", "cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-eks-protection-audit-enabled" = {
      identifier                  = "GUARDDUTY_EKS_PROTECTION_AUDIT_ENABLED"
      description                 = "GuardDuty.5: Checks if Audit Log Monitoring for Amazon Elastic Kubernetes Service (Amazon EKS) is enabled for an Amazon GuardDuty detector in your account."
      controls                    = ["GuardDuty.5"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1"]
    }
    "guardduty-eks-protection-runtime-enabled" = {
      identifier                  = "GUARDDUTY_EKS_PROTECTION_RUNTIME_ENABLED"
      description                 = "GuardDuty.7: Checks if Amazon EKS Runtime Monitoring with automated agent management is enabled for GuardDuty detector in your account."
      controls                    = ["GuardDuty.7"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-enabled-centralized" = {
      identifier                  = "GUARDDUTY_ENABLED_CENTRALIZED"
      description                 = "GuardDuty.1: Checks if Amazon GuardDuty is enabled in your AWS account and AWS Region."
      controls                    = ["GuardDuty.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ap-southeast-7", "mx-central-1"]
    }
    "guardduty-lambda-protection-enabled" = {
      identifier                  = "GUARDDUTY_LAMBDA_PROTECTION_ENABLED"
      description                 = "GuardDuty.6: Checks if Lambda Protection is enabled for an Amazon GuardDuty detector in your account."
      controls                    = ["GuardDuty.6"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1"]
    }
    "guardduty-malware-protection-enabled" = {
      identifier                  = "GUARDDUTY_MALWARE_PROTECTION_ENABLED"
      description                 = "GuardDuty.8: Checks if Malware Protection is enabled for an Amazon GuardDuty detector in your account."
      controls                    = ["GuardDuty.8"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-rds-protection-enabled" = {
      identifier                  = "GUARDDUTY_RDS_PROTECTION_ENABLED"
      description                 = "GuardDuty.9: Checks if Amazon Relational Database Service (Amazon RDS) protection is enabled for an Amazon GuardDuty detector in your account."
      controls                    = ["GuardDuty.9"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ca-west-1", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-runtime-monitoring-enabled" = {
      identifier                  = "GUARDDUTY_RUNTIME_MONITORING_ENABLED"
      description                 = "GuardDuty.11: Checks if Runtime Monitoring is enabled for Amazon GuardDuty detector in your account or organization."
      controls                    = ["GuardDuty.11"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ca-west-1", "cn-north-1", "cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "guardduty-s3-protection-enabled" = {
      identifier                  = "GUARDDUTY_S3_PROTECTION_ENABLED"
      description                 = "GuardDuty.10: Checks if S3 Protection is enabled for an Amazon GuardDuty Detector in your account."
      controls                    = ["GuardDuty.10"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["cn-north-1", "cn-northwest-1"]
    }
    "iam-customer-policy-blocked-kms-actions" = {
      identifier                  = "IAM_CUSTOMER_POLICY_BLOCKED_KMS_ACTIONS"
      description                 = "KMS.1: Checks if the managed AWS Identity and Access Management (IAM) policies that you create do not allow blocked actions on AWS KMS keys."
      controls                    = ["KMS.1"]
      trigger                     = "Configuration changes"
      global                      = true
      input_parameters            = { blockedActionsPatterns = "kms:Decrypt,kms:ReEncryptFrom", excludePermissionBoundaryPolicy = "true" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::IAM::Policy"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-password-policy" = {
      identifier                  = "IAM_PASSWORD_POLICY"
      description                 = "IAM.10, IAM.11, IAM.12, IAM.13, IAM.14, IAM.15, IAM.16, IAM.17, IAM.7: Checks if the account password policy for AWS Identity and Access Management (IAM) users meets the specified requirements indicated in the parameters."
      controls                    = ["IAM.10", "IAM.11", "IAM.12", "IAM.13", "IAM.14", "IAM.15", "IAM.16", "IAM.17", "IAM.7"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = { RequireUppercaseCharacters = "true", RequireLowercaseCharacters = "true", RequireSymbols = "true", RequireNumbers = "true", MinimumPasswordLength = "14", PasswordReusePrevention = "24", MaxPasswordAge = "90" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "iam-policy-in-use" = {
      identifier                  = "IAM_POLICY_IN_USE"
      description                 = "IAM.18: Checks whether the IAM policy ARN is attached to an IAM user, or a group with one or more IAM users, or an IAM role with one or more trusted entity."
      controls                    = ["IAM.18"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = { policyARN = "arn:${local.partition}:iam::aws:policy/AWSSupportAccess", policyUsageType = "ANY" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-policy-no-statements-with-admin-access" = {
      identifier                  = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
      description                 = "IAM.1: Checks if AWS Identity and Access Management (IAM) policies that you create have Allow statements that grant permissions to all actions on all resources."
      controls                    = ["IAM.1"]
      trigger                     = "Configuration changes"
      global                      = true
      input_parameters            = { excludePermissionBoundaryPolicy = "true" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::IAM::Policy"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-policy-no-statements-with-full-access" = {
      identifier                  = "IAM_POLICY_NO_STATEMENTS_WITH_FULL_ACCESS"
      description                 = "IAM.21: Checks if AWS Identity and Access Management (IAM) policies that you create grant permissions to all actions on individual AWS resources."
      controls                    = ["IAM.21"]
      trigger                     = "Configuration changes"
      global                      = true
      input_parameters            = { excludePermissionBoundaryPolicy = "true" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::IAM::Policy"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-root-access-key-check" = {
      identifier                  = "IAM_ROOT_ACCESS_KEY_CHECK"
      description                 = "IAM.4: Checks if the root user access key is available."
      controls                    = ["IAM.4"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-user-mfa-enabled" = {
      identifier                  = "IAM_USER_MFA_ENABLED"
      description                 = "IAM.19: Checks if the AWS Identity and Access Management (IAM) users have multi-factor authentication (MFA) enabled."
      controls                    = ["IAM.19"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-user-no-policies-check" = {
      identifier                  = "IAM_USER_NO_POLICIES_CHECK"
      description                 = "IAM.2: Checks if none of your AWS Identity and Access Management (IAM) users have policies attached."
      controls                    = ["IAM.2"]
      trigger                     = "Configuration changes"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::IAM::User"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "iam-user-unused-credentials-check" = {
      identifier                  = "IAM_USER_UNUSED_CREDENTIALS_CHECK"
      description                 = "IAM.8: Checks if your AWS Identity and Access Management (IAM) users have passwords or active access keys that have not been used within the specified number of days you provided."
      controls                    = ["IAM.8"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = { maxCredentialUsageAge = "90" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "inspector-ec2-scan-enabled" = {
      identifier                  = "INSPECTOR_EC2_SCAN_ENABLED"
      description                 = "Inspector.1: Checks if Amazon Inspector V2 EC2 scanning is activated for your single or multi-account environment to detect potential vulnerabilities and network reachability issues on your EC2 instances."
      controls                    = ["Inspector.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ap-southeast-6", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-south-2", "me-central-1", "mx-central-1"]
    }
    "inspector-ecr-scan-enabled" = {
      identifier                  = "INSPECTOR_ECR_SCAN_ENABLED"
      description                 = "Inspector.2: Checks if Amazon Inspector V2 ECR scanning is activated for your single or multi-account environment to detect potential software vulnerabilities in your container images."
      controls                    = ["Inspector.2"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ap-southeast-6", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-south-2", "me-central-1", "mx-central-1"]
    }
    "inspector-lambda-code-scan-enabled" = {
      identifier                  = "INSPECTOR_LAMBDA_CODE_SCAN_ENABLED"
      description                 = "Inspector.3: Checks if Amazon Inspector V2 Lambda code scanning is activated for your single or multi-account environment to detect potential code vulnerabilities."
      controls                    = ["Inspector.3"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = ["ap-northeast-1", "ap-southeast-1", "ap-southeast-2", "eu-central-1", "eu-north-1", "eu-west-1", "eu-west-2", "us-east-1", "us-east-2", "us-west-2"]
      except_regions              = []
    }
    "inspector-lambda-standard-scan-enabled" = {
      identifier                  = "INSPECTOR_LAMBDA_STANDARD_SCAN_ENABLED"
      description                 = "Inspector.4: Checks if Amazon Inspector V2 Lambda standard scanning is activated for your single or multi-account environment to detect potential software vulnerabilities."
      controls                    = ["Inspector.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ap-southeast-6", "ca-west-1", "cn-north-1", "cn-northwest-1", "eu-south-2", "me-central-1"]
    }
    "kms-key-policy-no-public-access" = {
      identifier                  = "KMS_KEY_POLICY_NO_PUBLIC_ACCESS"
      description                 = "KMS.5: Checks if the AWS KMS key policy allows public access."
      controls                    = ["KMS.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::KMS::Key"]
      only_regions                = []
      except_regions              = ["ca-west-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "lambda-function-public-access-prohibited" = {
      identifier                  = "LAMBDA_FUNCTION_PUBLIC_ACCESS_PROHIBITED"
      description                 = "Lambda.1: Checks if the AWS Lambda function policy attached to the Lambda resource prohibits public access."
      controls                    = ["Lambda.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Lambda::Function"]
      only_regions                = []
      except_regions              = ["cn-northwest-1"]
    }
    "lambda-function-settings-check" = {
      identifier                  = "LAMBDA_FUNCTION_SETTINGS_CHECK"
      description                 = "Lambda.2: Checks if the AWS Lambda function settings for runtime, role, timeout, and memory size match the expected values."
      controls                    = ["Lambda.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { runtime = "dotnet10,java25,java21,java17,java11,java8.al2,java17.al2023,java11.al2023,java8.al2023,nodejs26.x,nodejs24.x,nodejs22.x,python3.15,python3.14,python3.13,python3.12,python3.11,ruby4.0,ruby3.4,ruby3.3" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Lambda::Function"]
      only_regions                = []
      except_regions              = ["cn-northwest-1"]
    }
    "lambda-function-xray-enabled" = {
      identifier                  = "LAMBDA_FUNCTION_XRAY_ENABLED"
      description                 = "Lambda.7: Checks if AWS X-Ray is enabled on AWS Lambda functions.The rule is NON_COMPLIANT if X-Ray tracing is disabled for a Lambda function."
      controls                    = ["Lambda.7"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Lambda::Function"]
      only_regions                = []
      except_regions              = ["cn-northwest-1"]
    }
    "lambda-vpc-multi-az-check" = {
      identifier                  = "LAMBDA_VPC_MULTI_AZ_CHECK"
      description                 = "Lambda.5: Checks if Lambda has more than 1 availability zone associated."
      controls                    = ["Lambda.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::Lambda::Function"]
      only_regions                = []
      except_regions              = ["cn-northwest-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "mariadb-publish-logs-to-cloudwatch-logs" = {
      identifier                  = "MARIADB_PUBLISH_LOGS_TO_CLOUDWATCH_LOGS"
      description                 = "RDS.42: Checks if Amazon MariaDB database instances are configured to publish logs to Amazon CloudWatch Logs."
      controls                    = ["RDS.42"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "mfa-enabled-for-iam-console-access" = {
      identifier                  = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
      description                 = "IAM.5: Checks if AWS multi-factor authentication (MFA) is enabled for all AWS Identity and Access Management (IAM) users that use a console password."
      controls                    = ["IAM.5"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-4", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "il-central-1", "me-central-1", "mx-central-1"]
    }
    "multi-region-cloudtrail-enabled" = {
      identifier                  = "MULTI_REGION_CLOUD_TRAIL_ENABLED"
      description                 = "CloudTrail.1: Checks if there is at least one multi-region AWS CloudTrail."
      controls                    = ["CloudTrail.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { readWriteType = "ALL", includeManagementEvents = "true" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "nacl-no-unrestricted-ssh-rdp" = {
      identifier                  = "NACL_NO_UNRESTRICTED_SSH_RDP"
      description                 = "EC2.21: Checks if default ports for SSH/RDP ingress traffic for network access control lists (NACLs) is unrestricted."
      controls                    = ["EC2.21"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::NetworkAcl"]
      only_regions                = []
      except_regions              = []
    }
    "rds-automatic-minor-version-upgrade-enabled" = {
      identifier                  = "RDS_AUTOMATIC_MINOR_VERSION_UPGRADE_ENABLED"
      description                 = "RDS.13: Checks if Amazon Relational Database Service (RDS) database instances are configured for automatic minor version upgrades."
      controls                    = ["RDS.13"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-enhanced-monitoring-enabled" = {
      identifier                  = "RDS_ENHANCED_MONITORING_ENABLED"
      description                 = "RDS.6: Checks if enhanced monitoring is enabled for Amazon RDS instances."
      controls                    = ["RDS.6"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-instance-default-admin-check" = {
      identifier                  = "RDS_INSTANCE_DEFAULT_ADMIN_CHECK"
      description                 = "RDS.25: Checks if an Amazon Relational Database Service (Amazon RDS) database has changed the admin username from its default value."
      controls                    = ["RDS.25"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "mx-central-1"]
    }
    "rds-instance-deletion-protection-enabled" = {
      identifier                  = "RDS_INSTANCE_DELETION_PROTECTION_ENABLED"
      description                 = "RDS.8: Checks if an Amazon Relational Database Service (Amazon RDS) instance has deletion protection enabled."
      controls                    = ["RDS.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-instance-iam-authentication-enabled" = {
      identifier                  = "RDS_INSTANCE_IAM_AUTHENTICATION_ENABLED"
      description                 = "RDS.10: Checks if an Amazon Relational Database Service (Amazon RDS) instance has AWS Identity and Access Management (IAM) authentication enabled."
      controls                    = ["RDS.10"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-instance-public-access-check" = {
      identifier                  = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
      description                 = "RDS.2: Checks if the Amazon Relational Database Service (Amazon RDS) instances are not publicly accessible."
      controls                    = ["RDS.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-instance-subnet-igw-check" = {
      identifier                  = "RDS_INSTANCE_SUBNET_IGW_CHECK"
      description                 = "RDS.46: Checks if RDS DB instances are deployed in a public subnet with a route to the internet gateway."
      controls                    = ["RDS.46"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "rds-logging-enabled" = {
      identifier                  = "RDS_LOGGING_ENABLED"
      description                 = "RDS.9: Checks if respective logs of Amazon Relational Database Service (Amazon RDS) are enabled."
      controls                    = ["RDS.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-mariadb-instance-encrypted-in-transit" = {
      identifier                  = "RDS_MARIADB_INSTANCE_ENCRYPTED_IN_TRANSIT"
      description                 = "RDS.44: Checks if connections to Amazon RDS for MariaDB DB instances with engine version greater than or equal to 10.5 use encryption in transit."
      controls                    = ["RDS.44"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ca-west-1"]
    }
    "rds-multi-az-support" = {
      identifier                  = "RDS_MULTI_AZ_SUPPORT"
      description                 = "RDS.5: Checks whether high availability is enabled for your RDS DB instances."
      controls                    = ["RDS.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "rds-mysql-instance-encrypted-in-transit" = {
      identifier                  = "RDS_MYSQL_INSTANCE_ENCRYPTED_IN_TRANSIT"
      description                 = "RDS.39: Checks if connections to Amazon RDS for MySQL database instances are configured to use encryption in transit."
      controls                    = ["RDS.39"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ca-west-1"]
    }
    "rds-postgres-instance-encrypted-in-transit" = {
      identifier                  = "RDS_POSTGRES_INSTANCE_ENCRYPTED_IN_TRANSIT"
      description                 = "RDS.38: Checks if connections to Amazon RDS PostgreSQL database instances are configured to use encryption in transit."
      controls                    = ["RDS.38"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-5", "ap-southeast-7", "ca-west-1", "mx-central-1"]
    }
    "rds-postgresql-logs-to-cloudwatch" = {
      identifier                  = "RDS_POSTGRESQL_LOGS_TO_CLOUDWATCH"
      description                 = "RDS.36: Checks if an Amazon PostgreSQL DB instance is configured to publish logs to Amazon CloudWatch Logs."
      controls                    = ["RDS.36"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = ["ca-west-1"]
    }
    "rds-proxy-tls-encryption" = {
      identifier                  = "RDS_PROXY_TLS_ENCRYPTION"
      description                 = "RDS.43: Checks if Amazon RDS proxies enforce TLS for all connections."
      controls                    = ["RDS.43"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "us-gov-east-1", "us-gov-west-1"]
    }
    "rds-resources-protected-by-backup-plan" = {
      identifier                  = "RDS_RESOURCES_PROTECTED_BY_BACKUP_PLAN"
      description                 = "RDS.26: Checks if Amazon Relational Database Service (Amazon RDS) instances are protected by a backup plan."
      controls                    = ["RDS.26"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "mx-central-1"]
    }
    "rds-snapshot-encrypted" = {
      identifier                  = "RDS_SNAPSHOT_ENCRYPTED"
      description                 = "RDS.4: Checks if Amazon Relational Database Service (Amazon RDS) DB snapshots are encrypted."
      controls                    = ["RDS.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBClusterSnapshot", "AWS::RDS::DBSnapshot"]
      only_regions                = []
      except_regions              = []
    }
    "rds-snapshots-public-prohibited" = {
      identifier                  = "RDS_SNAPSHOTS_PUBLIC_PROHIBITED"
      description                 = "RDS.1: Checks if Amazon Relational Database Service (Amazon RDS) snapshots are public."
      controls                    = ["RDS.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBClusterSnapshot", "AWS::RDS::DBSnapshot"]
      only_regions                = []
      except_regions              = ["af-south-1", "ap-southeast-4", "eu-central-2", "eu-south-1", "eu-south-2", "il-central-1"]
    }
    "rds-sql-server-logs-to-cloudwatch" = {
      identifier                  = "RDS_SQL_SERVER_LOGS_TO_CLOUDWATCH"
      description                 = "RDS.40: Checks if an Amazon SQL Server DB instance is configured to publish logs to Amazon CloudWatch Logs."
      controls                    = ["RDS.40"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "mx-central-1"]
    }
    "rds-sqlserver-encrypted-in-transit" = {
      identifier                  = "RDS_SQLSERVER_ENCRYPTED_IN_TRANSIT"
      description                 = "RDS.41: Checks if connections to Amazon RDS SQL server database instances are configured to use encryption in transit."
      controls                    = ["RDS.41"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "rds-storage-encrypted" = {
      identifier                  = "RDS_STORAGE_ENCRYPTED"
      description                 = "RDS.3: Checks if storage encryption is enabled for your Amazon Relational Database Service (Amazon RDS) DB instances."
      controls                    = ["RDS.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::RDS::DBInstance"]
      only_regions                = []
      except_regions              = []
    }
    "required-tags" = {
      identifier                  = "REQUIRED_TAGS"
      description                 = "Library baseline: Checks if your resources have the tags that you specify."
      controls                    = []
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { tag1Key = "Application", tag2Key = "Environment", tag3Key = "Name", tag4Key = "ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::ACM::Certificate", "AWS::AutoScaling::AutoScalingGroup", "AWS::CloudFormation::Stack", "AWS::CodeBuild::Project", "AWS::DynamoDB::Table", "AWS::EC2::CustomerGateway", "AWS::EC2::Instance", "AWS::EC2::InternetGateway", "AWS::EC2::NetworkAcl", "AWS::EC2::NetworkInterface", "AWS::EC2::RouteTable", "AWS::EC2::SecurityGroup", "AWS::EC2::Subnet", "AWS::EC2::Volume", "AWS::EC2::VPC", "AWS::EC2::VPNConnection", "AWS::EC2::VPNGateway", "AWS::ElasticLoadBalancing::LoadBalancer", "AWS::ElasticLoadBalancingV2::LoadBalancer", "AWS::RDS::DBInstance", "AWS::RDS::DBSecurityGroup", "AWS::RDS::DBSnapshot", "AWS::RDS::DBSubnetGroup", "AWS::RDS::EventSubscription", "AWS::Redshift::Cluster", "AWS::Redshift::ClusterParameterGroup", "AWS::Redshift::ClusterSecurityGroup", "AWS::Redshift::ClusterSnapshot", "AWS::Redshift::ClusterSubnetGroup", "AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "restricted-common-ports" = {
      identifier                  = "RESTRICTED_INCOMING_TRAFFIC"
      description                 = "EC2.14, EC2.19: Checks if the security groups in use do not allow unrestricted incoming Transmission Control Protocol (TCP) traffic to specified ports."
      controls                    = ["EC2.14", "EC2.19"]
      trigger                     = "Configuration changes and Periodic"
      global                      = false
      input_parameters            = { blockedPorts = "20,21,22,23,25,110,135,143,445,1433,1434,3000,3306,3389,4333,5000,5432,5500,5601,8080,8088,8888,9200,9300" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::SecurityGroup"]
      only_regions                = []
      except_regions              = []
    }
    "restricted-ssh" = {
      identifier                  = "INCOMING_SSH_DISABLED"
      description                 = "EC2.13: Checks if the incoming SSH traffic for the security groups is accessible."
      controls                    = ["EC2.13"]
      trigger                     = "Configuration changes and Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::SecurityGroup"]
      only_regions                = []
      except_regions              = []
    }
    "root-account-hardware-mfa-enabled" = {
      identifier                  = "ROOT_ACCOUNT_HARDWARE_MFA_ENABLED"
      description                 = "IAM.6: Checks if your AWS account is enabled to use multi-factor authentication (MFA) hardware device to sign in with root credentials."
      controls                    = ["IAM.6"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "root-account-mfa-enabled" = {
      identifier                  = "ROOT_ACCOUNT_MFA_ENABLED"
      description                 = "IAM.9: Checks if the root user of your AWS account requires multi-factor authentication for console sign-in."
      controls                    = ["IAM.9"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "cn-north-1", "cn-northwest-1", "il-central-1", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "s3-account-level-public-access-blocks-periodic" = {
      identifier                  = "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS_PERIODIC"
      description                 = "S3.1: Checks if the required public access block settings are configured at the account level."
      controls                    = ["S3.1"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-acl-prohibited" = {
      identifier                  = "S3_BUCKET_ACL_PROHIBITED"
      description                 = "S3.12: Checks if Amazon Simple Storage Service (Amazon S3) Buckets allow user permissions through access control lists (ACLs)."
      controls                    = ["S3.12"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-default-lock-enabled" = {
      identifier                  = "S3_BUCKET_DEFAULT_LOCK_ENABLED"
      description                 = "S3.15: Checks if the S3 bucket has lock enabled, by default."
      controls                    = ["S3.15"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-level-public-access-prohibited" = {
      identifier                  = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
      description                 = "S3.8: Checks if S3 buckets are publicly accessible."
      controls                    = ["S3.8"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-logging-enabled" = {
      identifier                  = "S3_BUCKET_LOGGING_ENABLED"
      description                 = "S3.9: Checks if logging is enabled for your S3 buckets."
      controls                    = ["S3.9"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-mfa-delete-enabled" = {
      identifier                  = "S3_BUCKET_MFA_DELETE_ENABLED"
      description                 = "S3.20: Checks if MFA Delete is enabled in the Amazon Simple Storage Service (Amazon S3) bucket versioning configuration."
      controls                    = ["S3.20"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-6", "ap-southeast-7", "ca-west-1", "mx-central-1"]
    }
    "s3-bucket-public-read-prohibited" = {
      identifier                  = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
      description                 = "S3.2: Checks if your Amazon S3 buckets do not allow public read access."
      controls                    = ["S3.2"]
      trigger                     = "Configuration changes and Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-public-write-prohibited" = {
      identifier                  = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
      description                 = "S3.3: Checks if your Amazon S3 buckets do not allow public write access."
      controls                    = ["S3.3"]
      trigger                     = "Configuration changes and Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-ssl-requests-only" = {
      identifier                  = "S3_BUCKET_SSL_REQUESTS_ONLY"
      description                 = "S3.5: Checks if S3 buckets have policies that require requests to use SSL/TLS."
      controls                    = ["S3.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-bucket-versioning-enabled" = {
      identifier                  = "S3_BUCKET_VERSIONING_ENABLED"
      description                 = "S3.14: Checks if versioning is enabled for your S3 buckets."
      controls                    = ["S3.14"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-default-encryption-kms" = {
      identifier                  = "S3_DEFAULT_ENCRYPTION_KMS"
      description                 = "S3.17: Checks if the S3 buckets are encrypted with AWS Key Management Service (AWS KMS)."
      controls                    = ["S3.17"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket", "AWS::KMS::Key"]
      only_regions                = []
      except_regions              = []
    }
    "s3-event-notifications-enabled" = {
      identifier                  = "S3_EVENT_NOTIFICATIONS_ENABLED"
      description                 = "S3.11: Checks if Amazon S3 Events Notifications are enabled on an S3 bucket."
      controls                    = ["S3.11"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = ["mx-central-1"]
    }
    "s3-lifecycle-policy-check" = {
      identifier                  = "S3_LIFECYCLE_POLICY_CHECK"
      description                 = "S3.13: Checks if a lifecycle rule is configured for an Amazon Simple Storage Service (Amazon S3) bucket."
      controls                    = ["S3.13"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "s3-version-lifecycle-policy-check" = {
      identifier                  = "S3_VERSION_LIFECYCLE_POLICY_CHECK"
      description                 = "S3.10: Checks if Amazon Simple Storage Service (Amazon S3) version enabled buckets have lifecycle policy configured."
      controls                    = ["S3.10"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::S3::Bucket"]
      only_regions                = []
      except_regions              = []
    }
    "secretsmanager-rotation-enabled-check" = {
      identifier                  = "SECRETSMANAGER_ROTATION_ENABLED_CHECK"
      description                 = "SecretsManager.1: Checks if AWS Secrets Manager secret has rotation enabled."
      controls                    = ["SecretsManager.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SecretsManager::Secret"]
      only_regions                = []
      except_regions              = []
    }
    "secretsmanager-scheduled-rotation-success-check" = {
      identifier                  = "SECRETSMANAGER_SCHEDULED_ROTATION_SUCCESS_CHECK"
      description                 = "SecretsManager.2: Checks if AWS Secrets Manager secrets rotated successfully according to the rotation schedule."
      controls                    = ["SecretsManager.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SecretsManager::Secret"]
      only_regions                = []
      except_regions              = []
    }
    "secretsmanager-secret-periodic-rotation" = {
      identifier                  = "SECRETSMANAGER_SECRET_PERIODIC_ROTATION"
      description                 = "SecretsManager.4: Checks if AWS Secrets Manager secrets have been rotated in the past specified number of days."
      controls                    = ["SecretsManager.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "secretsmanager-secret-unused" = {
      identifier                  = "SECRETSMANAGER_SECRET_UNUSED"
      description                 = "SecretsManager.3: Checks if AWS Secrets Manager secrets have been accessed within a specified number of days."
      controls                    = ["SecretsManager.3"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "secretsmanager-using-cmk" = {
      identifier                  = "SECRETSMANAGER_USING_CMK"
      description                 = "Library baseline: Checks if all secrets in AWS Secrets Manager are encrypted using the AWS managed key (aws/secretsmanager) or a customer managed key that was created in AWS Key Management Service (AWS KMS)."
      controls                    = []
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SecretsManager::Secret"]
      only_regions                = []
      except_regions              = []
    }
    "security-account-information-provided" = {
      identifier                  = "SECURITY_ACCOUNT_INFORMATION_PROVIDED"
      description                 = "Account.1: Checks if you have provided security contact information for your AWS account contacts."
      controls                    = ["Account.1"]
      trigger                     = "Periodic"
      global                      = true
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ca-west-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "sns-encrypted-kms" = {
      identifier                  = "SNS_ENCRYPTED_KMS"
      description                 = "SNS.1: Checks if SNS topics are encrypted with AWS Key Management Service (AWS KMS)."
      controls                    = ["SNS.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SNS::Topic"]
      only_regions                = []
      except_regions              = []
    }
    "sns-topic-no-public-access" = {
      identifier                  = "SNS_TOPIC_NO_PUBLIC_ACCESS"
      description                 = "SNS.4: Checks if the SNS topic access policy allows public access."
      controls                    = ["SNS.4"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SNS::Topic"]
      only_regions                = []
      except_regions              = ["ca-west-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "sqs-queue-no-public-access" = {
      identifier                  = "SQS_QUEUE_NO_PUBLIC_ACCESS"
      description                 = "SQS.3: Checks if the SQS queue access policy allows public access."
      controls                    = ["SQS.3"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SQS::Queue"]
      only_regions                = []
      except_regions              = ["ap-south-2", "ap-southeast-4", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "ssm-automation-block-public-sharing" = {
      identifier                  = "SSM_AUTOMATION_BLOCK_PUBLIC_SHARING"
      description                 = "SSM.7: Checks if AWS Systems Manager Documents has block public sharing enabled."
      controls                    = ["SSM.7"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = ["ap-southeast-4"]
    }
    "ssm-automation-logging-enabled" = {
      identifier                  = "SSM_AUTOMATION_LOGGING_ENABLED"
      description                 = "SSM.6: Checks if AWS Systems Manager Automation has Amazon CloudWatch logging enabled."
      controls                    = ["SSM.6"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "ssm-document-not-public" = {
      identifier                  = "SSM_DOCUMENT_NOT_PUBLIC"
      description                 = "SSM.4: Checks if AWS Systems Manager documents owned by the account are public."
      controls                    = ["SSM.4"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "ssm-document-tagged" = {
      identifier                  = "SSM_DOCUMENT_TAGGED"
      description                 = "SSM.5: Checks if AWS Systems Manager documents have tags."
      controls                    = ["SSM.5"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = { requiredKeyTags = "Application,Environment,Name,ManagedBy" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::SSM::Document"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-southeast-5", "ap-southeast-6", "ap-southeast-7", "cn-north-1", "cn-northwest-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "step-functions-state-machine-logging-enabled" = {
      identifier                  = "STEP_FUNCTIONS_STATE_MACHINE_LOGGING_ENABLED"
      description                 = "StepFunctions.1: Checks if AWS Step Functions machine has logging enabled."
      controls                    = ["StepFunctions.1"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::StepFunctions::StateMachine"]
      only_regions                = []
      except_regions              = ["ap-southeast-4", "ca-west-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
    "subnet-auto-assign-public-ip-disabled" = {
      identifier                  = "SUBNET_AUTO_ASSIGN_PUBLIC_IP_DISABLED"
      description                 = "EC2.15: Checks if Amazon Virtual Private Cloud (Amazon VPC) subnets are configured to automatically assign public IP addresses to instances launched within them."
      controls                    = ["EC2.15"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::Subnet"]
      only_regions                = []
      except_regions              = []
    }
    "vpc-default-security-group-closed" = {
      identifier                  = "VPC_DEFAULT_SECURITY_GROUP_CLOSED"
      description                 = "EC2.2: Checks if the default security group of any Amazon Virtual Private Cloud (Amazon VPC) does not allow inbound or outbound traffic."
      controls                    = ["EC2.2"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::SecurityGroup"]
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ec2" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.10: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.10"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ec2" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ecr-api" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.55: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.55"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ecr.api" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ecr-dkr" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.56: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.56"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ecr.dkr" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ssm" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.57: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.57"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ssm" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ssm-contacts" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.58: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.58"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ssm-contacts" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-endpoint-enabled-ssm-incidents" = {
      identifier                  = "VPC_ENDPOINT_ENABLED"
      description                 = "EC2.60: Checks if each service specified in the parameter has an Amazon VPC endpoint."
      controls                    = ["EC2.60"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = { serviceNames = "ssm-incidents" }
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-flow-logs-enabled" = {
      identifier                  = "VPC_FLOW_LOGS_ENABLED"
      description                 = "EC2.6: Checks if Amazon Virtual Private Cloud (Amazon VPC) flow logs are found and enabled for all Amazon VPCs."
      controls                    = ["EC2.6"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "vpc-network-acl-unused-check" = {
      identifier                  = "VPC_NETWORK_ACL_UNUSED_CHECK"
      description                 = "EC2.16: Checks if there are unused network access control lists (network ACLs)."
      controls                    = ["EC2.16"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::NetworkAcl"]
      only_regions                = []
      except_regions              = []
    }
    "vpc-sg-open-only-to-authorized-ports" = {
      identifier                  = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
      description                 = "EC2.18: Checks if security groups allowing unrestricted incoming traffic ('0.0.0.0/0' or '::/0') only allow inbound TCP or UDP connections on authorized ports."
      controls                    = ["EC2.18"]
      trigger                     = "Configuration changes and Periodic"
      global                      = false
      input_parameters            = { authorizedTcpPorts = "80,443" }
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::EC2::SecurityGroup"]
      only_regions                = []
      except_regions              = []
    }
    "vpc-sg-port-restriction-check" = {
      identifier                  = "VPC_SG_PORT_RESTRICTION_CHECK"
      description                 = "EC2.53, EC2.54: Checks if security groups restrict incoming traffic to restricted ports explicitly from 0.0.0.0/0 or ::/0."
      controls                    = ["EC2.53", "EC2.54"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "wafv2-logging-enabled" = {
      identifier                  = "WAFV2_LOGGING_ENABLED"
      description                 = "WAF.11: Checks if logging is enabled on AWS WAFv2 regional and global web access control lists (web ACLs)."
      controls                    = ["WAF.11"]
      trigger                     = "Periodic"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = "TwentyFour_Hours"
      resource_types_scope        = []
      only_regions                = []
      except_regions              = []
    }
    "wafv2-webacl-not-empty" = {
      identifier                  = "WAFV2_WEBACL_NOT_EMPTY"
      description                 = "WAF.10: Checks if a WAFv2 Web ACL contains any WAF rules or WAF rule groups."
      controls                    = ["WAF.10"]
      trigger                     = "Configuration changes"
      global                      = false
      input_parameters            = {}
      maximum_execution_frequency = null
      resource_types_scope        = ["AWS::WAFv2::WebACL"]
      only_regions                = []
      except_regions              = ["ap-east-2", "ap-south-2", "ap-southeast-7", "ca-west-1", "eu-central-2", "eu-south-2", "me-central-1", "mx-central-1", "us-gov-east-1", "us-gov-west-1"]
    }
  }
}
