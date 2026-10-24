mock_provider "aws" {
  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-workers-eks-node-role"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 3
    }
  }
}

variables {
  application  = "core"
  environment  = "prod"
  name         = "workers"
  cluster_name = "core-prod-k8s"
  kms_key_arn  = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"

  node_groups = {
    general = {
      subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      instance_types = ["m7i.large"]
      scaling_config = {
        min_size     = 2
        max_size     = 4
        desired_size = 2
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].node_group_name == "core-prod-workers-general"
    error_message = "Node group name did not match <application>-<environment>-<name>-<key>."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].name == "core-prod-workers-node-general"
    error_message = "Launch template name did not match <rendered_name>-node-<key>."
  }

  assert {
    condition     = aws_iam_role.node_group.name == "core-prod-workers-eks-node-role"
    error_message = "Node IAM role name did not match <rendered_name>-eks-node-role."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].cluster_name == "core-prod-k8s"
    error_message = "Node groups must attach to var.cluster_name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_eks_node_group.this["general"].node_group_name == "core-prod-general"
    error_message = "A null name must fall back to <application>-<environment>-<key>."
  }

  assert {
    condition     = aws_iam_role.node_group.name == "core-prod-eks-node-role"
    error_message = "Node IAM role name must use the fallback rendered name."
  }

  assert {
    condition     = aws_iam_role.node_group.tags["Name"] == "core-prod"
    error_message = "Name tag must use the fallback rendered name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].name == "core-prod-node-general"
    error_message = "An empty name must fall back to <application>-<environment>."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
      Owner      = "platform-team"
    }
  }

  assert {
    condition = (
      aws_iam_role.node_group.tags["Application"] == "core" &&
      aws_iam_role.node_group.tags["Environment"] == "prod" &&
      aws_iam_role.node_group.tags["Name"] == "core-prod-workers"
    )
    error_message = "Node IAM role must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition = (
      aws_eks_node_group.this["general"].tags["Application"] == "core" &&
      aws_eks_node_group.this["general"].tags["Environment"] == "prod" &&
      aws_eks_node_group.this["general"].tags["Name"] == "core-prod-workers-general"
    )
    error_message = "Node group must carry the governance tags with Name overridden to the node group name."
  }

  assert {
    condition = alltrue([
      for spec in aws_launch_template.eks_node_group["general"].tag_specifications :
      spec.tags["Application"] == "core" && spec.tags["Environment"] == "prod" && spec.tags["Name"] == "core-prod-workers-general"
    ])
    error_message = "Instance and volume tag specifications must carry the governance tags with Name overridden to the node group name."
  }

  assert {
    condition     = toset([for spec in aws_launch_template.eks_node_group["general"].tag_specifications : spec.resource_type]) == toset(["instance", "volume"])
    error_message = "The launch template must tag both instances and volumes."
  }

  assert {
    condition = alltrue([
      for t in concat(
        [aws_iam_role.node_group.tags, aws_eks_node_group.this["general"].tags],
        [for spec in aws_launch_template.eks_node_group["general"].tag_specifications : spec.tags],
      ) :
      t["CostCenter"] == "platform" && t["Owner"] == "platform-team"
    ])
    error_message = "Caller tags from var.tags must be preserved on the role, node group, instances and volumes."
  }
}

# ------------------------------------------------------------------------------
# Security and shipped defaults
# ------------------------------------------------------------------------------
run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_launch_template.eks_node_group["general"].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced with http_tokens = required."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].metadata_options[0].http_endpoint == "enabled"
    error_message = "The instance metadata endpoint must stay enabled for IMDSv2."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Root volumes must be encrypted."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Root volumes must be encrypted with var.kms_key_arn."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].block_device_mappings[0].ebs[0].delete_on_termination == "true"
    error_message = "Root volumes must be deleted on instance termination."
  }

  assert {
    condition     = jsondecode(aws_iam_role.node_group.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "The node role must only be assumable by ec2.amazonaws.com."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.node_worker.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" &&
      aws_iam_role_policy_attachment.node_cni.policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" &&
      aws_iam_role_policy_attachment.node_registry.policy_arn == "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    )
    error_message = "The node role must have exactly the worker, CNI and read-only ECR managed policies attached."
  }
}

run "verify_shipped_defaults" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].ami_type == "AL2023_x86_64_STANDARD"
    error_message = "AMI type must default to AL2023_x86_64_STANDARD."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].capacity_type == "ON_DEMAND"
    error_message = "Capacity type must default to ON_DEMAND."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].force_update_version == true
    error_message = "force_update_version must be true."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].update_config[0].max_unavailable == 1
    error_message = "Rolling updates must replace at most one node at a time."
  }

  assert {
    condition     = length(aws_eks_node_group.this["general"].taint) == 0
    error_message = "No taints should be applied by default."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].instance_types == tolist(["m7i.large"])
    error_message = "instance_types did not flow through."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "subnet_ids did not flow through."
  }

  assert {
    condition = (
      aws_eks_node_group.this["general"].scaling_config[0].min_size == 2 &&
      aws_eks_node_group.this["general"].scaling_config[0].max_size == 4 &&
      aws_eks_node_group.this["general"].scaling_config[0].desired_size == 2
    )
    error_message = "scaling_config did not flow through."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["general"].block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "The root block device must be /dev/xvda."
  }

  assert {
    condition = (
      aws_launch_template.eks_node_group["general"].block_device_mappings[0].ebs[0].volume_type == "gp3" &&
      aws_launch_template.eks_node_group["general"].block_device_mappings[0].ebs[0].volume_size == 50
    )
    error_message = "Root volumes must default to 50 GiB gp3."
  }
}

run "verify_empty_node_groups_create_only_the_role" {
  command = plan

  variables {
    node_groups = {}
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 0 && length(aws_launch_template.eks_node_group) == 0
    error_message = "No node groups or launch templates should be created for an empty node_groups map."
  }

  assert {
    condition     = aws_iam_role.node_group.name == "core-prod-workers-eks-node-role"
    error_message = "The node IAM role must still be created for an empty node_groups map."
  }

  assert {
    condition     = output.node_group_arns == {} && output.launch_template_ids == {}
    error_message = "Node group outputs must be empty maps when no node groups are configured."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------
run "verify_optional_inputs_flow_through" {
  command = plan

  variables {
    node_groups = {
      general = {
        subnet_ids     = ["subnet-0123456789abcdef0"]
        instance_types = ["m7i.large"]
        scaling_config = {
          min_size     = 2
          max_size     = 4
          desired_size = 2
        }
      }
      spot = {
        subnet_ids          = ["subnet-0fedcba9876543210"]
        instance_types      = ["m7g.xlarge", "m6g.xlarge"]
        ami_type            = "AL2023_ARM_64_STANDARD"
        capacity_type       = "SPOT"
        ami_release_version = "1.30.4-20240917"
        labels = {
          tier = "batch"
        }
        taints = [
          {
            key    = "dedicated"
            value  = "batch"
            effect = "NO_SCHEDULE"
          }
        ]
        scaling_config = {
          min_size     = 0
          max_size     = 10
          desired_size = 1
        }
        root_volume = {
          size       = 100
          iops       = 4000
          throughput = 250
        }
      }
    }
  }

  assert {
    condition     = keys(aws_eks_node_group.this) == ["general", "spot"] && keys(aws_launch_template.eks_node_group) == ["general", "spot"]
    error_message = "Each node_groups entry must get its own node group and launch template."
  }

  assert {
    condition = (
      aws_eks_node_group.this["spot"].ami_type == "AL2023_ARM_64_STANDARD" &&
      aws_eks_node_group.this["spot"].capacity_type == "SPOT" &&
      aws_eks_node_group.this["spot"].release_version == "1.30.4-20240917"
    )
    error_message = "AMI type, capacity type and release version overrides did not flow through."
  }

  assert {
    condition     = aws_eks_node_group.this["spot"].instance_types == tolist(["m7g.xlarge", "m6g.xlarge"])
    error_message = "instance_types override did not flow through."
  }

  assert {
    condition     = aws_eks_node_group.this["spot"].labels == tomap({ tier = "batch" })
    error_message = "Labels did not flow through."
  }

  assert {
    condition = (
      one(aws_eks_node_group.this["spot"].taint).key == "dedicated" &&
      one(aws_eks_node_group.this["spot"].taint).value == "batch" &&
      one(aws_eks_node_group.this["spot"].taint).effect == "NO_SCHEDULE"
    )
    error_message = "Taints did not flow through."
  }

  assert {
    condition = (
      aws_eks_node_group.this["spot"].scaling_config[0].min_size == 0 &&
      aws_eks_node_group.this["spot"].scaling_config[0].max_size == 10 &&
      aws_eks_node_group.this["spot"].scaling_config[0].desired_size == 1
    )
    error_message = "scaling_config override did not flow through."
  }

  assert {
    condition = (
      aws_launch_template.eks_node_group["spot"].block_device_mappings[0].ebs[0].volume_size == 100 &&
      aws_launch_template.eks_node_group["spot"].block_device_mappings[0].ebs[0].iops == 4000 &&
      aws_launch_template.eks_node_group["spot"].block_device_mappings[0].ebs[0].throughput == 250
    )
    error_message = "Root volume size, IOPS and throughput overrides did not flow through."
  }

  assert {
    condition     = aws_launch_template.eks_node_group["spot"].block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Root volume encryption must not be affected by root_volume overrides."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].capacity_type == "ON_DEMAND"
    error_message = "Overrides on one node group must not leak into another."
  }
}

# ------------------------------------------------------------------------------
# Wiring and outputs (needs computed values)
# ------------------------------------------------------------------------------
run "verify_launch_template_and_role_wiring" {
  command   = apply
  state_key = "verify_launch_template_and_role_wiring"

  assert {
    condition     = aws_eks_node_group.this["general"].launch_template[0].id == aws_launch_template.eks_node_group["general"].id
    error_message = "Node groups must use their module-created launch template."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].launch_template[0].version == "3"
    error_message = "Node groups must pin the launch template's latest version."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].node_role_arn == aws_iam_role.node_group.arn
    error_message = "Node groups must use the module-created node role."
  }

  assert {
    condition     = output.node_role_arn == "arn:aws:iam::123456789012:role/core-prod-workers-eks-node-role"
    error_message = "node_role_arn output must expose the node role ARN."
  }

  assert {
    condition     = output.node_group_arns == { general = aws_eks_node_group.this["general"].arn }
    error_message = "node_group_arns output must map node group keys to node group ARNs."
  }

  assert {
    condition     = output.node_group_ids == { general = aws_eks_node_group.this["general"].id }
    error_message = "node_group_ids output must map node group keys to node group IDs."
  }

  assert {
    condition     = output.launch_template_ids == { general = "lt-0123456789abcdef0" }
    error_message = "launch_template_ids output must map node group keys to launch template IDs."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_invalid_application_fails" {
  command = plan

  variables {
    application = "Core_App"
  }

  expect_failures = [var.application]
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "sandbox"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_kms_key_arn_fails" {
  command = plan

  variables {
    kms_key_arn = "12345678-1234-1234-1234-123456789012"
  }

  expect_failures = [var.kms_key_arn]
}
