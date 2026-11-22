mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-etl-job-eu-west-1"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/core-prod-etl-instance-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/batch/core-prod-etl"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0bbbbbbbbbbbbbbbb"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  mock_resource "aws_batch_compute_environment" {
    defaults = {
      arn = "arn:aws:batch:eu-west-1:123456789012:compute-environment/core-prod-etl-fargate"
    }
  }

  mock_resource "aws_batch_scheduling_policy" {
    defaults = {
      arn = "arn:aws:batch:eu-west-1:123456789012:scheduling-policy/core-prod-etl-fair-share"
    }
  }

  mock_resource "aws_batch_job_definition" {
    defaults = {
      arn        = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-etl-nightly:1"
      arn_prefix = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-etl-nightly"
    }
  }
}

variables {
  application              = "core"
  environment              = "prod"
  name                     = "etl"
  tags                     = { Team = "data" }
  readonly_root_filesystem = true
}

run "nothing_without_inputs" {
  command = plan

  assert {
    condition     = length(aws_batch_compute_environment.this) + length(aws_batch_job_queue.this) + length(aws_batch_job_definition.this) + length(aws_batch_scheduling_policy.this) + length(aws_launch_template.this) == 0
    error_message = "No inputs means no Batch resources."
  }

  assert {
    condition     = length(module.job_role) + length(module.execution_role) + length(module.instance_role) + length(module.log_group) + length(module.security_group) == 0
    error_message = "Roles, log group and security group exist only when something needs them."
  }

  assert {
    condition     = output.role_arn == null && output.execution_role_arn == null && output.log_group_name == null && output.security_group_id == null && output.kms_key_arn == null
    error_message = "Outputs are null without resources."
  }
}

run "fargate_stack" {
  command = apply

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    compute_environments = {
      fargate = { max_vcpus = 16 }
    }
    job_queues = {
      default = { priority = 1, compute_environments = ["fargate"] }
    }
    job_definitions = {
      nightly = {
        image           = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-etl:1.0.0"
        command         = ["python", "run.py"]
        vcpu            = 0.5
        memory          = 1024
        user            = "1000:1000"
        environment     = { LOG_LEVEL = "info" }
        secrets         = { DB_URL = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf:url::", API = "/core/prod/api-key" }
        writable_paths  = ["/tmp"]
        timeout_seconds = 3600
        attempts        = 3
      }
    }
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].name_prefix == "core-prod-etl-fargate-" && aws_batch_compute_environment.this["fargate"].type == "MANAGED" && aws_batch_compute_environment.this["fargate"].compute_resources[0].type == "FARGATE"
    error_message = "Fargate compute environment named <application>-<environment>-<name>-<key>-."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].compute_resources[0].instance_role == null && length(aws_batch_compute_environment.this["fargate"].compute_resources[0].launch_template) == 0 && length(aws_launch_template.this) == 0 && length(module.instance_role) == 0
    error_message = "Fargate needs no instance role or launch template."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].compute_resources[0].security_group_ids == toset(["sg-0bbbbbbbbbbbbbbbb"]) && keys(module.security_group[0].egress_rule_ids) == ["https-0"] && length(module.security_group[0].ingress_rule_ids) == 0
    error_message = "The module security group has egress only."
  }

  assert {
    condition     = local.egress_rules["https-0"].ip_protocol == "tcp" && local.egress_rules["https-0"].from_port == 443 && local.egress_rules["https-0"].to_port == 443 && local.egress_rules["https-0"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "Default egress is TCP 443 only, for image pulls and AWS APIs."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].tags["Name"] == "core-prod-etl-fargate" && aws_batch_compute_environment.this["fargate"].tags["Team"] == "data" && aws_batch_compute_environment.this["fargate"].tags["ManagedBy"] == "Terraform"
    error_message = "Compute environments must carry caller and governance tags (Batch.3)."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].name == "core-prod-etl-default" && aws_batch_job_queue.this["default"].compute_environment_order[0].compute_environment == "arn:aws:batch:eu-west-1:123456789012:compute-environment/core-prod-etl-fargate" && aws_batch_job_queue.this["default"].tags["ManagedBy"] == "Terraform" && aws_batch_job_queue.this["default"].scheduling_policy_arn == null
    error_message = "The queue must use the module compute environment and carry governance tags (Batch.1)."
  }

  assert {
    condition     = aws_batch_job_definition.this["nightly"].name == "core-prod-etl-nightly" && aws_batch_job_definition.this["nightly"].platform_capabilities == toset(["FARGATE"]) && aws_batch_job_definition.this["nightly"].propagate_tags && aws_batch_job_definition.this["nightly"].retry_strategy[0].attempts == 3 && aws_batch_job_definition.this["nightly"].timeout[0].attempt_duration_seconds == 3600
    error_message = "Job definition name, platform, retries and timeout."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).readonlyRootFilesystem && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).user == "1000:1000" && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).networkConfiguration.assignPublicIp == "DISABLED" && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).fargatePlatformConfiguration.platformVersion == "LATEST"
    error_message = "Containers run read-only, non-root, without a public IP, on the latest platform."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).resourceRequirements == [{ type = "VCPU", value = "0.5" }, { type = "MEMORY", value = "1024" }] && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).command == ["python", "run.py"]
    error_message = "vCPU, memory and command must be rendered."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).mountPoints == [{ sourceVolume = "scratch-0", containerPath = "/tmp", readOnly = false }] && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).volumes == [{ name = "scratch-0" }]
    error_message = "writable_paths must mount scratch volumes."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).logConfiguration == { logDriver = "awslogs", options = { "awslogs-group" = "/aws/batch/core-prod-etl", "awslogs-region" = "eu-west-1", "awslogs-stream-prefix" = "nightly" } }
    error_message = "Jobs must log to the module log group."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).jobRoleArn == output.role_arn && jsondecode(aws_batch_job_definition.this["nightly"].container_properties).executionRoleArn == output.execution_role_arn && output.role_arn != null
    error_message = "Jobs must use the module roles."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/batch/core-prod-etl" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null
    error_message = "Logs: /aws/batch/<base>, 365 days, service encryption by default."
  }

  assert {
    condition     = output.job_definition_arn_prefixes["nightly"] == "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-etl-nightly" && output.job_queue_names["default"] == "core-prod-etl-default"
    error_message = "Outputs must expose queues and job definitions."
  }
}

run "execution_and_job_roles" {
  command = plan

  variables {
    job_definitions = {
      nightly = {
        image   = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-etl:1.0.0"
        secrets = { DB_URL = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf:url::", API = "/core/prod/api-key" }
      }
    }
  }

  assert {
    condition     = [for s in jsondecode(module.execution_role[0].policy_json).Statement : s.Sid] == ["WriteLogs", "GetRegistryToken", "PullImages", "ReadSecrets", "ReadParameters", "DecryptSecrets"]
    error_message = "The execution role must get logs, image pulls and secrets only."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/batch/core-prod-etl:*"] && jsondecode(module.execution_role[0].policy_json).Statement[2].Resource == ["arn:aws:ecr:eu-west-1:123456789012:repository/core-prod-etl"]
    error_message = "Logs and image pulls must be scoped to the log group and repository."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[3].Resource == ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf"] && jsondecode(module.execution_role[0].policy_json).Statement[4].Resource == ["arn:aws:ssm:eu-west-1:123456789012:parameter/core/prod/api-key"] && jsondecode(module.execution_role[0].policy_json).Statement[4].Action == ["ssm:GetParameters"]
    error_message = "Secrets Manager and SSM references must become secret and parameter ARNs."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[5].Condition.StringEquals["kms:ViaService"] == ["secretsmanager.eu-west-1.amazonaws.com", "ssm.eu-west-1.amazonaws.com"]
    error_message = "kms:Decrypt must be limited to Secrets Manager and SSM."
  }

  assert {
    condition     = module.execution_role[0].name == "core-prod-etl-batch-exec-eu-west-1" && module.job_role[0].name == "core-prod-etl-job-eu-west-1" && module.job_role[0].policy_json == null
    error_message = "Roles named <base>-<purpose>-<region>; the job role has no permissions by default."
  }

  assert {
    condition     = jsondecode(module.job_role[0].trust_policy_json).Statement[0].Principal.Service == ["ecs-tasks.amazonaws.com"] && jsondecode(module.job_role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.job_role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:ecs:eu-west-1:123456789012:*"]
    error_message = "Only ECS tasks in this account may assume the job role."
  }
}

run "ec2_environments_with_module_key" {
  command   = apply
  state_key = "ec2"

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    kms        = { create = true }
    compute_environments = {
      ondemand = { type = "EC2", max_vcpus = 64, min_vcpus = 2, instance_types = ["c7i"], root_volume_size = 50 }
      spot     = { type = "SPOT", max_vcpus = 128 }
    }
    job_definitions = {
      gpu = { image = "public.ecr.aws/docker/library/python:3.13", platform = "EC2", readonly_root_filesystem = false }
    }
  }

  assert {
    condition     = aws_launch_template.this["ondemand"].metadata_options[0].http_tokens == "required" && aws_launch_template.this["ondemand"].metadata_options[0].http_put_response_hop_limit == 1
    error_message = "Instances must require IMDSv2 with hop limit 1."
  }

  assert {
    condition     = aws_launch_template.this["ondemand"].block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this["ondemand"].block_device_mappings[0].ebs[0].volume_type == "gp3" && aws_launch_template.this["ondemand"].block_device_mappings[0].ebs[0].volume_size == 50 && aws_launch_template.this["ondemand"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "Root volumes must be encrypted gp3 with the module key."
  }

  assert {
    condition     = aws_launch_template.this["spot"].tag_specifications[0].tags["ManagedBy"] == "Terraform" && aws_launch_template.this["spot"].tag_specifications[1].resource_type == "volume" && aws_launch_template.this["spot"].tag_specifications[1].tags["Application"] == "core"
    error_message = "Instances and volumes must carry governance tags."
  }

  assert {
    condition     = aws_batch_compute_environment.this["ondemand"].compute_resources[0].instance_role == "arn:aws:iam::123456789012:instance-profile/core-prod-etl-instance-eu-west-1" && aws_batch_compute_environment.this["ondemand"].compute_resources[0].allocation_strategy == "BEST_FIT_PROGRESSIVE" && aws_batch_compute_environment.this["ondemand"].compute_resources[0].min_vcpus == 2 && aws_batch_compute_environment.this["ondemand"].compute_resources[0].instance_type == toset(["c7i"])
    error_message = "EC2 environments use the instance profile and BEST_FIT_PROGRESSIVE."
  }

  assert {
    condition     = aws_batch_compute_environment.this["spot"].compute_resources[0].allocation_strategy == "SPOT_PRICE_CAPACITY_OPTIMIZED" && aws_batch_compute_environment.this["spot"].compute_resources[0].ec2_configuration[0].image_type == "ECS_AL2023" && aws_batch_compute_environment.this["spot"].compute_resources[0].launch_template[0].launch_template_id == "lt-0123456789abcdef0"
    error_message = "Spot environments use price-capacity-optimized, AL2023 and the launch template."
  }

  assert {
    condition     = aws_batch_compute_environment.this["spot"].compute_resources[0].tags["ManagedBy"] == "Terraform" && aws_batch_compute_environment.this["spot"].compute_resources[0].tags["Name"] == "core-prod-etl-spot"
    error_message = "EC2 compute resources must be tagged (Batch.4)."
  }

  assert {
    condition     = module.instance_role[0].instance_profile_arn != null && jsondecode(module.instance_role[0].trust_policy_json).Statement[0].Principal.Service == ["ec2.amazonaws.com"]
    error_message = "EC2 environments get an instance profile trusted by EC2."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The module key must encrypt the log group."
  }

  assert {
    condition     = !jsondecode(aws_batch_job_definition.this["gpu"].container_properties).privileged && !jsondecode(aws_batch_job_definition.this["gpu"].container_properties).readonlyRootFilesystem && !can(jsondecode(aws_batch_job_definition.this["gpu"].container_properties).networkConfiguration)
    error_message = "EC2 jobs are unprivileged; the per-job read-only override applies."
  }

  assert {
    condition     = !contains([for s in jsondecode(module.execution_role[0].policy_json).Statement : s.Sid], "PullImages")
    error_message = "Images outside ECR need no pull permission."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    kms        = { create = true }
    compute_environments = {
      ondemand = { type = "EC2", max_vcpus = 8 }
    }
    job_definitions = {
      nightly = { image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-etl:1.0.0" }
    }
  }

  assert {
    condition     = module.encryption.created && length(aws_launch_template.this) == 1 && length(module.log_group) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
    job_definitions = {
      nightly = { image = "busybox:1.37" }
    }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention."
  }
}

run "logs_disabled" {
  command = apply

  variables {
    cloudwatch_logs = { enabled = false }
    job_definitions = {
      nightly = { image = "busybox:1.37" }
    }
  }

  assert {
    condition     = length(module.log_group) == 0 && output.log_group_name == null && !can(jsondecode(aws_batch_job_definition.this["nightly"].container_properties).logConfiguration)
    error_message = "cloudwatch_logs.enabled = false removes the log group and log configuration."
  }

  assert {
    condition     = [for s in jsondecode(module.execution_role[0].policy_json).Statement : s.Sid] == ["GetRegistryToken"]
    error_message = "Without logs, ECR images or secrets the execution role only gets a registry token."
  }
}

run "scheduling_policy_and_queue_order" {
  command = apply

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    compute_environments = {
      fargate = { max_vcpus = 16 }
    }
    scheduling_policy = {
      enabled             = true
      share_decay_seconds = 3600
      share_distribution  = [{ share_identifier = "high", weight_factor = 0.5 }]
    }
    job_queues = {
      default  = { priority = 10, compute_environments = ["fargate", "arn:aws:batch:eu-west-1:123456789012:compute-environment/shared"] }
      external = { priority = 1, compute_environments = ["arn:aws:batch:eu-west-1:123456789012:compute-environment/shared"], scheduling_policy_arn = "arn:aws:batch:eu-west-1:123456789012:scheduling-policy/shared" }
    }
  }

  assert {
    condition     = aws_batch_scheduling_policy.this[0].name == "core-prod-etl-fair-share" && aws_batch_scheduling_policy.this[0].fair_share_policy[0].share_decay_seconds == 3600 && aws_batch_scheduling_policy.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "The scheduling policy must be named and tagged (Batch.2)."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].scheduling_policy_arn == "arn:aws:batch:eu-west-1:123456789012:scheduling-policy/core-prod-etl-fair-share" && aws_batch_job_queue.this["external"].scheduling_policy_arn == "arn:aws:batch:eu-west-1:123456789012:scheduling-policy/shared"
    error_message = "Queues use the module policy unless they name their own."
  }

  assert {
    condition     = [for o in aws_batch_job_queue.this["default"].compute_environment_order : o.order] == [0, 1] && aws_batch_job_queue.this["default"].compute_environment_order[1].compute_environment == "arn:aws:batch:eu-west-1:123456789012:compute-environment/shared"
    error_message = "Compute environments keep their order; ARNs pass through."
  }
}

run "egress_override" {
  command   = apply
  state_key = "egress"

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group = {
      egress_cidr_blocks        = ["10.0.0.0/16", "2001:db8::/56"]
      egress_prefix_list_ids    = ["pl-0123456789abcdef0"]
      egress_security_group_ids = ["sg-0eeeeeeeeeeeeeeee"]
    }
    compute_environments = { fargate = { max_vcpus = 4 } }
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["https-0", "https-1", "pl-0", "sg-0"]
    error_message = "egress_cidr_blocks replace the HTTPS destinations; prefix lists and groups add destinations."
  }

  assert {
    condition     = local.egress_rules["https-0"].cidr_ipv4 == "10.0.0.0/16" && local.egress_rules["https-0"].from_port == 443 && local.egress_rules["https-1"].cidr_ipv6 == "2001:db8::/56" && local.egress_rules["https-1"].cidr_ipv4 == null
    error_message = "CIDR destinations get HTTPS only, IPv4 or IPv6."
  }

  assert {
    condition     = local.egress_rules["sg-0"].ip_protocol == "-1" && local.egress_rules["sg-0"].referenced_security_group_id == "sg-0eeeeeeeeeeeeeeee" && local.egress_rules["pl-0"].prefix_list_id == "pl-0123456789abcdef0"
    error_message = "Listed groups and prefix lists are reached on every port."
  }
}

run "efs_volumes" {
  command   = apply
  state_key = "efs"

  variables {
    job_definitions = {
      nightly = {
        image          = "busybox:1.37"
        writable_paths = ["/tmp"]
        efs_volumes = {
          shared  = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", container_path = "/mnt/shared" }
          reports = { file_system_id = "fs-0fedcba9876543210", root_directory = "/reports", container_path = "/mnt/reports", read_only = true }
        }
      }
      export = {
        image       = "busybox:1.37"
        efs_volumes = { shared = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-0aaaaaaaaaaaaaaaa", container_path = "/mnt/shared", read_only = true } }
      }
      cleanup = { image = "busybox:1.37" }
    }
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).volumes == [{ name = "scratch-0" }, { name = "reports", efsVolumeConfiguration = { fileSystemId = "fs-0fedcba9876543210", rootDirectory = "/reports", transitEncryption = "ENABLED", authorizationConfig = { iam = "DISABLED" } } }, { name = "shared", efsVolumeConfiguration = { fileSystemId = "fs-0123456789abcdef0", transitEncryption = "ENABLED", authorizationConfig = { iam = "ENABLED", accessPointId = "fsap-00000000000000001" } } }]
    error_message = "EFS volumes always use TLS; IAM authorization with an access point."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).mountPoints == [{ sourceVolume = "scratch-0", containerPath = "/tmp", readOnly = false }, { sourceVolume = "reports", containerPath = "/mnt/reports", readOnly = true }, { sourceVolume = "shared", containerPath = "/mnt/shared", readOnly = false }]
    error_message = "Each EFS volume is mounted at container_path, read-only when asked."
  }

  assert {
    condition     = !can(jsondecode(aws_batch_job_definition.this["cleanup"].container_properties).volumes) && !can(jsondecode(aws_batch_job_definition.this["cleanup"].container_properties).mountPoints)
    error_message = "Jobs without volumes render none."
  }

  assert {
    condition     = [for s in jsondecode(module.job_role[0].policy_json).Statement : s.Sid] == ["MountEfs0", "MountEfs1", "MountEfs2"]
    error_message = "The job role gets one mount statement per EFS volume of every job."
  }

  assert {
    condition     = jsondecode(module.job_role[0].policy_json).Statement[0].Action == ["elasticfilesystem:ClientMount"] && jsondecode(module.job_role[0].policy_json).Statement[0].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0123456789abcdef0"] && jsondecode(module.job_role[0].policy_json).Statement[0].Condition.StringEquals["elasticfilesystem:AccessPointArn"] == "arn:aws:elasticfilesystem:eu-west-1:123456789012:access-point/fsap-0aaaaaaaaaaaaaaaa"
    error_message = "A read-only access point mount gets ClientMount on that access point only."
  }

  assert {
    condition     = jsondecode(module.job_role[0].policy_json).Statement[1].Action == ["elasticfilesystem:ClientMount"] && jsondecode(module.job_role[0].policy_json).Statement[1].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0fedcba9876543210"] && !can(jsondecode(module.job_role[0].policy_json).Statement[1].Condition)
    error_message = "A read-only mount without an access point gets ClientMount on the file system."
  }

  assert {
    condition     = jsondecode(module.job_role[0].policy_json).Statement[2].Action == ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"] && jsondecode(module.job_role[0].policy_json).Statement[2].Condition.StringEquals["elasticfilesystem:AccessPointArn"] == "arn:aws:elasticfilesystem:eu-west-1:123456789012:access-point/fsap-00000000000000001"
    error_message = "A writable access point mount adds ClientWrite."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["nightly"].container_properties).jobRoleArn == output.role_arn && output.role_arn == "arn:aws:iam::123456789012:role/core-prod-etl-job-eu-west-1"
    error_message = "Jobs run as the role that carries the mount permissions."
  }
}

run "efs_with_module_key_is_planned_safely" {
  command = plan

  variables {
    vpc_id               = "vpc-0a1b2c3d4e5f67890"
    subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    kms                  = { create = true }
    compute_environments = { fargate = { max_vcpus = 4 } }
    job_definitions = {
      nightly = { image = "busybox:1.37", efs_volumes = { shared = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", container_path = "/mnt/shared" } } }
    }
  }

  assert {
    condition     = module.encryption.created && length(module.job_role) == 1 && length(aws_batch_job_definition.this) == 1
    error_message = "EFS volumes and mount permissions must plan without knowing the key ARN."
  }

  assert {
    condition     = keys(local.egress_rules) == ["https-0", "nfs"] && local.egress_rules["nfs"].ip_protocol == "tcp" && local.egress_rules["nfs"].from_port == 2049 && local.egress_rules["nfs"].to_port == 2049 && local.egress_rules["nfs"].cidr_ipv4 == "10.0.0.0/16" && length(data.aws_vpc.this) == 1
    error_message = "EFS volumes add NFS egress to the VPC CIDR only."
  }
}

run "bring_your_own_job_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-batch-job" }
    job_definitions = {
      nightly = { image = "busybox:1.37" }
    }
  }

  assert {
    condition     = length(module.job_role) == 0 && output.role_arn == "arn:aws:iam::123456789012:role/shared-batch-job" && output.role_name == null
    error_message = "A caller role must replace the job role."
  }
}

run "extend_the_job_role" {
  command = plan

  variables {
    iam_role = {
      managed_policy_arns      = ["arn:aws:iam::123456789012:policy/etl-read"]
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "ReadInput", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::core-prod-input/*"] }]
    }
    job_definitions = {
      nightly = { image = "busybox:1.37" }
    }
  }

  assert {
    condition     = [for s in jsondecode(module.job_role[0].policy_json).Statement : s.Sid] == ["ReadInput"]
    error_message = "Caller statements go to the job role."
  }
}

run "external_security_groups_only" {
  command = plan

  variables {
    subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group       = { create = false, additional_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"] }
    compute_environments = { fargate = { max_vcpus = 4 } }
  }

  assert {
    condition     = length(module.security_group) == 0 && aws_batch_compute_environment.this["fargate"].compute_resources[0].security_group_ids == toset(["sg-0aaaaaaaaaaaaaaaa"])
    error_message = "create = false uses only the caller groups."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "ETL_Jobs"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_missing_vpc" {
  command = plan

  variables {
    subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    compute_environments = { fargate = { max_vcpus = 4 } }
  }

  expect_failures = [var.vpc_id]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    vpc_id               = "vpc-0a1b2c3d4e5f67890"
    subnet_ids           = ["subnet-0123456789abcdef0"]
    compute_environments = { fargate = { max_vcpus = 4 } }
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/batch" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_compute_environment_key" {
  command = plan

  variables {
    compute_environments = { Fargate_1 = { max_vcpus = 4 } }
  }

  expect_failures = [var.compute_environments]
}

run "rejects_unknown_compute_type" {
  command = plan

  variables {
    compute_environments = { x = { type = "EKS", max_vcpus = 4 } }
  }

  expect_failures = [var.compute_environments]
}

run "rejects_invalid_vcpus" {
  command = plan

  variables {
    compute_environments = { x = { type = "EC2", max_vcpus = 4, min_vcpus = 8 } }
  }

  expect_failures = [var.compute_environments]
}

run "rejects_invalid_compute_state" {
  command = plan

  variables {
    compute_environments = { x = { max_vcpus = 4, state = "OFF" } }
  }

  expect_failures = [var.compute_environments]
}

run "rejects_invalid_queue_key" {
  command = plan

  variables {
    job_queues = { High_Priority = { priority = 1, compute_environments = ["x"] } }
  }

  expect_failures = [var.job_queues]
}

run "rejects_queue_without_environment" {
  command = plan

  variables {
    job_queues = { default = { priority = 1, compute_environments = [] } }
  }

  expect_failures = [var.job_queues]
}

run "rejects_invalid_queue_state" {
  command = plan

  variables {
    job_queues = { default = { priority = 1, compute_environments = ["x"], state = "PAUSED" } }
  }

  expect_failures = [var.job_queues]
}

run "rejects_invalid_job_key" {
  command = plan

  variables {
    job_definitions = { Nightly_Job = { image = "busybox:1.37" } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_unknown_platform" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", platform = "EKS" } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_credentials_in_environment" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", environment = { DB_PASSWORD = "x" } } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_root_user" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", user = "0:0" } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_invalid_retry_and_timeout" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", timeout_seconds = 30 } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_efs_volume_named_like_scratch" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", efs_volumes = { scratch-0 = { file_system_id = "fs-0123456789abcdef0", container_path = "/mnt/data" } } } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_invalid_efs_ids_and_path" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", efs_volumes = { data = { file_system_id = "fs-0123456789abcdef0", access_point_id = "ap-1", container_path = "mnt/data" } } } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_root_directory_with_access_point" {
  command = plan

  variables {
    job_definitions = { nightly = { image = "busybox:1.37", efs_volumes = { data = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", root_directory = "/data", container_path = "/mnt/data" } } } }
  }

  expect_failures = [var.job_definitions]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}
