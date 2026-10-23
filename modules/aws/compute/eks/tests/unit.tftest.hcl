mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-k8s-mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/core-prod-k8s-mock"
    }
  }

  # certificate_authority is a computed list the outputs index into.
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-west-2:123456789012:cluster/core-prod-k8s"
      endpoint = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-west-2.eks.amazonaws.com"
      certificate_authority = [
        {
          data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
        }
      ]
    }
  }

  mock_resource "aws_eks_node_group" {
    defaults = {
      arn = "arn:aws:eks:us-west-2:123456789012:nodegroup/core-prod-k8s/core-prod-k8s-general/0123456789abcdef"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }
}

variables {
  application              = "core"
  environment              = "prod"
  name                     = "k8s"
  kms_key_arn              = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  control_plane_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_cluster_name" {
  command = plan

  assert {
    condition     = output.cluster_name == "core-prod-k8s"
    error_message = "Cluster name did not match <application>-<environment>-<name>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = output.cluster_name == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = output.cluster_name == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }
}

# ------------------------------------------------------------------------------
# Security and shipped defaults
# ------------------------------------------------------------------------------
run "verify_secure_input_defaults" {
  command = plan

  assert {
    condition     = var.endpoint_public_access == false
    error_message = "The wrapper must default to a private-only API endpoint."
  }

  assert {
    condition     = length(var.public_access_cidrs) == 0
    error_message = "The wrapper must not open any public CIDRs by default."
  }

  assert {
    condition     = var.cluster_version == "1.30"
    error_message = "The wrapper cluster_version must default to 1.30."
  }

  assert {
    condition     = length(var.security_group_ids) == 0
    error_message = "The wrapper must not attach additional security groups by default."
  }
}

run "verify_node_groups_off_by_default" {
  command = plan

  assert {
    condition     = length(module.node_group) == 0
    error_message = "The node_group submodule must not be instantiated when node_groups is empty."
  }

  assert {
    condition     = output.node_group_arns == {} && output.node_group_ids == {}
    error_message = "Node group outputs must be empty maps when no node groups are configured."
  }

  assert {
    condition     = output.node_role_arn == null
    error_message = "node_role_arn must be null when no node groups are configured."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides and wiring
# ------------------------------------------------------------------------------
run "verify_node_groups_created_when_configured" {
  command   = apply
  state_key = "verify_node_groups_created_when_configured"

  variables {
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
      batch = {
        subnet_ids     = ["subnet-0fedcba9876543210"]
        instance_types = ["m7i.xlarge"]
        capacity_type  = "SPOT"
        scaling_config = {
          min_size     = 0
          max_size     = 10
          desired_size = 1
        }
      }
    }
  }

  assert {
    condition     = length(module.node_group) == 1
    error_message = "The node_group submodule must be instantiated once when node_groups is set."
  }

  assert {
    condition     = keys(output.node_group_arns) == ["batch", "general"] && keys(output.node_group_ids) == ["batch", "general"]
    error_message = "Node group outputs must have one entry per node_groups key."
  }

  assert {
    condition     = output.node_group_arns == module.node_group[0].node_group_arns
    error_message = "node_group_arns must pass through the node_group submodule output."
  }

  assert {
    condition     = output.node_role_arn == module.node_group[0].node_role_arn && output.node_role_arn != null
    error_message = "node_role_arn must pass through the node_group submodule output."
  }

  assert {
    condition     = keys(module.node_group[0].launch_template_ids) == ["batch", "general"]
    error_message = "Each node group must get its own launch template."
  }
}

run "verify_cluster_outputs_pass_through" {
  command   = apply
  state_key = "verify_cluster_outputs_pass_through"

  assert {
    condition     = output.cluster_arn == "arn:aws:eks:us-west-2:123456789012:cluster/core-prod-k8s"
    error_message = "cluster_arn must pass through the cluster submodule output."
  }

  assert {
    condition     = output.cluster_endpoint == "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-west-2.eks.amazonaws.com"
    error_message = "cluster_endpoint must pass through the cluster submodule output."
  }

  assert {
    condition     = output.cluster_certificate_authority_data == "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    error_message = "cluster_certificate_authority_data must pass through the cluster submodule output."
  }

  assert {
    condition     = output.cluster_role_arn == module.cluster.cluster_role_arn && output.cluster_role_arn != null
    error_message = "cluster_role_arn must pass through the cluster submodule output."
  }

  assert {
    condition     = output.cluster_security_group_id == module.cluster.cluster_security_group_id
    error_message = "cluster_security_group_id must pass through the cluster submodule output."
  }

  assert {
    condition     = output.node_role_arn == null
    error_message = "node_role_arn must stay null when no node groups are configured."
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
    kms_key_arn = "arn:aws:s3:::core-prod-bucket"
  }

  expect_failures = [var.kms_key_arn]
}
