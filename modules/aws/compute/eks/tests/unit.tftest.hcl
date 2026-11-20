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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-cluster-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/eks/core-prod/cluster"
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

  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:eu-west-1:123456789012:cluster/core-prod"
      endpoint              = "https://ABCDEF.gr7.eu-west-1.eks.amazonaws.com"
      certificate_authority = [{ data = "LS0tLS1CRUdJTg==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.eu-west-1.amazonaws.com/id/ABCDEF" }] }]
    }
  }

  mock_resource "aws_eks_node_group" {
    defaults = {
      node_group_name = "core-prod-general-20261119000000000000000001"
      resources       = [{ autoscaling_groups = [{ name = "eks-core-prod-general-asg" }], remote_access_security_group_id = "" }]
    }
  }

  mock_resource "aws_eks_access_entry" {
    defaults = {
      access_entry_arn = "arn:aws:eks:eu-west-1:123456789012:access-entry/core-prod/role/123456789012/platform-admins/abc"
    }
  }
}

variables {
  application     = "core"
  environment     = "prod"
  tags            = { Team = "platform" }
  cluster_version = "1.37"
  vpc_id          = "vpc-0a1b2c3d4e5f67890"
  subnet_ids      = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "core-prod" && aws_eks_cluster.this.version == "1.37" && aws_eks_cluster.this.deletion_protection && !aws_eks_cluster.this.bootstrap_self_managed_addons
    error_message = "Cluster <application>-<environment>, pinned version, deletion protection."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && !aws_eks_cluster.this.vpc_config[0].endpoint_public_access
    error_message = "The API endpoint is private by default (EKS.1)."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Access entries only, creator admin bootstrapped."
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit", "authenticator", "controllerManager", "scheduler"]) && module.log_group[0].name == "/aws/eks/core-prod/cluster" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null
    error_message = "All control plane logs, including audit (EKS.8), kept 365 days."
  }

  assert {
    condition     = length(aws_eks_cluster.this.encryption_config) == 0 && output.kms_key_arn == null && aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "No kms input keeps the EKS default envelope encryption."
  }

  assert {
    condition     = aws_eks_cluster.this.tags["Name"] == "core-prod" && aws_eks_cluster.this.tags["Team"] == "platform" && aws_eks_cluster.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags (EKS.6)."
  }

  assert {
    condition     = keys(aws_eks_addon.before_compute) == ["eks-pod-identity-agent", "kube-proxy", "vpc-cni"] && keys(aws_eks_addon.this) == ["aws-ebs-csi-driver", "aws-efs-csi-driver", "coredns", "snapshot-controller"]
    error_message = "Default add-ons, CNI and Pod Identity agent before the nodes."
  }

  assert {
    condition     = keys(module.addon_role) == ["ebs-csi", "efs-csi", "efs-csi-node", "vpc-cni"] && length(module.lb_controller_role) == 1 && length(aws_eks_pod_identity_association.lb_controller) == 1
    error_message = "Add-on and Load Balancer Controller roles exist with add-ons on."
  }

  assert {
    condition     = length(module.node_role) + length(aws_eks_node_group.this) + length(aws_launch_template.this) + length(module.fargate_role) + length(aws_eks_access_entry.this) == 0 && output.node_role_arn == null
    error_message = "No nodes, Fargate profiles or access entries by default."
  }
}

run "cluster_role" {
  command = plan

  assert {
    condition     = module.cluster_role.name == "core-prod-cluster-eu-west-1" && jsondecode(module.cluster_role.trust_policy_json).Statement[0].Principal.Service == ["eks.amazonaws.com"]
    error_message = "Cluster role <base>-cluster-<region>, trusted by EKS."
  }

  assert {
    condition     = jsondecode(module.cluster_role.trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.cluster_role.trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:eks:eu-west-1:123456789012:cluster/core-prod"]
    error_message = "Only this cluster may assume the cluster role."
  }
}

run "public_endpoint" {
  command = plan

  variables {
    name                         = "apps"
    endpoint_public_access_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.name == "core-prod-apps" && aws_eks_cluster.this.vpc_config[0].endpoint_public_access && aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    error_message = "The public endpoint opens only to the listed CIDRs."
  }
}

run "api_security_group" {
  command = apply

  variables {
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16"]
      additional_security_group_ids = ["sg-0ccccccccccccccccc"]
    }
  }

  assert {
    condition     = keys(module.security_group[0].ingress_rule_ids) == ["cidr-0", "sg-0"] && length(module.security_group[0].egress_rule_ids) == 0
    error_message = "API ingress only from the listed sources; no egress."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].security_group_ids == toset(["sg-0bbbbbbbbbbbbbbbb", "sg-0ccccccccccccccccc"]) && output.security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "The cluster uses the module group and the extra groups."
  }

  assert {
    condition     = output.endpoint == "https://ABCDEF.gr7.eu-west-1.eks.amazonaws.com" && output.certificate_authority_data == "LS0tLS1CRUdJTg==" && output.oidc_issuer_url == "https://oidc.eks.eu-west-1.amazonaws.com/id/ABCDEF" && output.arn == "arn:aws:eks:eu-west-1:123456789012:cluster/core-prod"
    error_message = "Cluster connection outputs."
  }
}

run "node_groups_with_module_key" {
  command   = apply
  state_key = "nodes"

  variables {
    kms = { create = true }
    node_groups = {
      general = { instance_types = ["m7i.large"], min_size = 2, max_size = 6, labels = { role = "general" } }
      bottle  = { instance_types = ["c7g.large"], ami_type = "BOTTLEROCKET_ARM_64", capacity_type = "SPOT", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], taints = [{ key = "dedicated", value = "batch", effect = "NO_SCHEDULE" }] }
    }
  }

  assert {
    condition     = aws_launch_template.this["general"].metadata_options[0].http_tokens == "required" && aws_launch_template.this["general"].metadata_options[0].http_put_response_hop_limit == 2
    error_message = "Nodes require IMDSv2 with hop limit 2."
  }

  assert {
    condition     = aws_launch_template.this["general"].block_device_mappings[0].device_name == "/dev/xvda" && aws_launch_template.this["general"].block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this["general"].block_device_mappings[0].ebs[0].volume_type == "gp3" && aws_launch_template.this["general"].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "Root volumes are encrypted gp3 with the module key."
  }

  assert {
    condition     = aws_launch_template.this["bottle"].block_device_mappings[0].device_name == "/dev/xvdb"
    error_message = "Bottlerocket encrypts its data volume."
  }

  assert {
    condition     = aws_launch_template.this["general"].tag_specifications[0].resource_type == "instance" && aws_launch_template.this["general"].tag_specifications[0].tags["ManagedBy"] == "Terraform" && aws_launch_template.this["general"].tag_specifications[1].resource_type == "volume" && aws_launch_template.this["general"].tag_specifications[1].tags["Application"] == "core"
    error_message = "Instances and volumes carry governance tags."
  }

  assert {
    condition     = aws_eks_node_group.this["general"].node_group_name_prefix == "core-prod-general-" && aws_eks_node_group.this["general"].version == "1.37" && aws_eks_node_group.this["general"].scaling_config[0].desired_size == 2 && aws_eks_node_group.this["general"].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "Node groups follow the cluster version (EKS.9) and start at min_size."
  }

  assert {
    condition     = aws_eks_node_group.this["bottle"].capacity_type == "SPOT" && aws_eks_node_group.this["bottle"].subnet_ids == toset(["subnet-0aaaaaaaaaaaaaaaa"]) && length(aws_eks_node_group.this["bottle"].taint) == 1 && aws_eks_node_group.this["bottle"].launch_template[0].id == "lt-0123456789abcdef0"
    error_message = "Per-group capacity type, subnets, taints and launch template."
  }

  assert {
    condition     = module.node_role[0].name == "core-prod-node-eu-west-1" && jsondecode(module.node_role[0].trust_policy_json).Statement[0].Principal.Service == ["ec2.amazonaws.com"] && output.node_role_arn != null
    error_message = "Node role <base>-node-<region>, trusted by EC2."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"]) && module.log_group[0].kms_key_arn == output.kms_key_arn
    error_message = "The module key encrypts secrets and logs."
  }

  assert {
    condition     = output.autoscaling_group_names["general"] == ["eks-core-prod-general-asg"] && output.launch_template_ids["general"] == "lt-0123456789abcdef0" && output.node_group_names["general"] != null
    error_message = "Node group outputs for alarms."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms         = { create = true }
    node_groups = { general = { instance_types = ["m7i.large"] } }
  }

  assert {
    condition     = module.encryption.created && length(aws_eks_cluster.this.encryption_config) == 1 && length(aws_launch_template.this) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "caller_key_id_and_log_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731, log_types = ["audit"] }
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731 && aws_eks_cluster.this.enabled_cluster_log_types == toset(["audit"])
    error_message = "cloudwatch_logs must override the log key, retention and log types."
  }
}

run "no_control_plane_logs" {
  command = plan

  variables {
    cloudwatch_logs = { log_types = [] }
  }

  assert {
    condition     = length(module.log_group) == 0 && output.log_group_name == null && length(aws_eks_cluster.this.enabled_cluster_log_types) == 0
    error_message = "No log types means no log group."
  }
}

run "access_entries" {
  command = apply

  variables {
    bootstrap_cluster_creator_admin_permissions = false
    access_entries = {
      admins = {
        principal_arn       = "arn:aws:iam::123456789012:role/platform-admins"
        policy_associations = { admin = { policy = "AmazonEKSClusterAdminPolicy" } }
      }
      team = {
        principal_arn       = "arn:aws:iam::123456789012:role/orders-team"
        kubernetes_groups   = ["orders-readers"]
        policy_associations = { edit = { policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy", namespaces = ["orders"] } }
      }
    }
  }

  assert {
    condition     = !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions && aws_eks_access_entry.this["admins"].type == "STANDARD" && aws_eks_access_entry.this["team"].kubernetes_groups == toset(["orders-readers"])
    error_message = "Access entries per principal."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["admins/admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" && aws_eks_access_policy_association.this["admins/admin"].access_scope[0].type == "cluster"
    error_message = "Policy names expand to access policy ARNs with cluster scope."
  }

  assert {
    condition     = aws_eks_access_policy_association.this["team/edit"].access_scope[0].type == "namespace" && aws_eks_access_policy_association.this["team/edit"].access_scope[0].namespaces == toset(["orders"]) && aws_eks_access_policy_association.this["team/edit"].principal_arn == "arn:aws:iam::123456789012:role/orders-team"
    error_message = "Namespaces scope a policy to those namespaces."
  }
}

run "pod_identities" {
  command = plan

  variables {
    pod_identities = {
      orders = {
        namespace         = "orders"
        service_account   = "orders-api"
        policy_statements = [{ sid = "ReadOrders", actions = ["dynamodb:GetItem"], resources = ["arn:aws:dynamodb:eu-west-1:123456789012:table/orders"] }]
      }
      shared = { namespace = "tools", service_account = "runner", role_arn = "arn:aws:iam::123456789012:role/shared-runner" }
    }
  }

  assert {
    condition     = keys(module.workload_role) == ["orders"] && module.workload_role["orders"].name == "core-prod-orders-pod-eu-west-1" && [for s in jsondecode(module.workload_role["orders"].policy_json).Statement : s.Sid] == ["ReadOrders"]
    error_message = "Statements create a workload role; role_arn is used as given."
  }

  assert {
    condition     = jsondecode(module.workload_role["orders"].trust_policy_json).Statement[0].Principal.Service == ["pods.eks.amazonaws.com"] && jsondecode(module.workload_role["orders"].trust_policy_json).Statement[0].Action == ["sts:AssumeRole", "sts:TagSession"]
    error_message = "Workload roles trust EKS Pod Identity."
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["orders"].namespace == "orders" && aws_eks_pod_identity_association.this["orders"].service_account == "orders-api" && aws_eks_pod_identity_association.this["shared"].role_arn == "arn:aws:iam::123456789012:role/shared-runner"
    error_message = "Associations bind namespace and service account."
  }
}

run "addon_roles" {
  command = plan

  assert {
    condition     = module.addon_role["vpc-cni"].name == "core-prod-vpc-cni-eu-west-1" && jsondecode(module.addon_role["vpc-cni"].trust_policy_json).Statement[0].Action == ["sts:AssumeRole", "sts:TagSession"] && module.addon_role["vpc-cni"].policy_json == null
    error_message = "Add-on roles trust Pod Identity and use managed policies."
  }

  assert {
    condition     = jsondecode(module.addon_role["efs-csi-node"].policy_json).Statement[0].Condition.Bool["elasticfilesystem:AccessedViaMountTarget"] == "true"
    error_message = "The EFS node role mounts only through mount targets."
  }

  assert {
    condition     = contains([for s in jsondecode(module.lb_controller_role[0].policy_json).Statement : s.Sid], "ElbServiceLinkedRole") && aws_eks_pod_identity_association.lb_controller[0].service_account == "aws-load-balancer-controller"
    error_message = "The Load Balancer Controller role is bound to its service account."
  }

  assert {
    condition     = jsondecode(aws_eks_addon.before_compute["vpc-cni"].configuration_values).env.ENABLE_PREFIX_DELEGATION == "true" && [for a in aws_eks_addon.before_compute["vpc-cni"].pod_identity_association : a.service_account] == ["aws-node"] && length(aws_eks_addon.before_compute["kube-proxy"].pod_identity_association) == 0
    error_message = "VPC CNI uses prefix delegation and its own Pod Identity role."
  }

  assert {
    condition     = toset([for a in aws_eks_addon.this["aws-efs-csi-driver"].pod_identity_association : a.service_account]) == toset(["efs-csi-controller-sa", "efs-csi-node-sa"])
    error_message = "The EFS CSI driver binds controller and node roles."
  }
}

run "addon_overrides_and_s3_csi" {
  command = plan

  variables {
    addons = {
      versions             = { coredns = "v1.12.4-eksbuild.1" }
      configuration_values = { coredns = "{\"replicaCount\":3}" }
      s3_csi_bucket_arns   = ["arn:aws:s3:::core-prod-models"]
      s3_csi_kms_key_arns  = ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    }
  }

  assert {
    condition     = aws_eks_addon.this["coredns"].addon_version == "v1.12.4-eksbuild.1" && jsondecode(aws_eks_addon.this["coredns"].configuration_values).replicaCount == 3
    error_message = "Versions and configuration values override the defaults."
  }

  assert {
    condition     = contains(keys(aws_eks_addon.this), "aws-mountpoint-s3-csi-driver") && [for s in jsondecode(module.addon_role["s3-csi"].policy_json).Statement : s.Sid] == ["MountpointListBuckets", "MountpointObjectAccess", "MountpointSseKms"]
    error_message = "Bucket ARNs install the S3 CSI driver with a scoped role."
  }

  assert {
    condition     = jsondecode(module.addon_role["s3-csi"].policy_json).Statement[1].Resource == ["arn:aws:s3:::core-prod-models/*"] && jsondecode(module.addon_role["s3-csi"].policy_json).Statement[2].Condition.StringEquals["kms:ViaService"] == "s3.eu-west-1.amazonaws.com"
    error_message = "Object access only in the listed buckets; KMS only through S3."
  }
}

run "addons_disabled" {
  command = plan

  variables {
    addons      = { enabled = false }
    node_groups = { general = { instance_types = ["m7i.large"] } }
  }

  assert {
    condition     = length(aws_eks_addon.before_compute) + length(aws_eks_addon.this) + length(module.addon_role) + length(module.lb_controller_role) + length(aws_eks_pod_identity_association.lb_controller) == 0
    error_message = "addons.enabled = false removes add-ons and their roles."
  }
}

run "fargate_profiles" {
  command = plan

  variables {
    fargate_profiles = {
      jobs = { selectors = [{ namespace = "jobs", labels = { runtime = "fargate" } }] }
    }
  }

  assert {
    condition     = aws_eks_fargate_profile.this["jobs"].fargate_profile_name == "core-prod-jobs" && aws_eks_fargate_profile.this["jobs"].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]) && length(aws_eks_fargate_profile.this["jobs"].selector) == 1
    error_message = "Fargate profiles use the cluster subnets by default."
  }

  assert {
    condition     = jsondecode(module.fargate_role[0].trust_policy_json).Statement[0].Principal.Service == ["eks-fargate-pods.amazonaws.com"] && jsondecode(module.fargate_role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:eks:eu-west-1:123456789012:fargateprofile/core-prod/*"]
    error_message = "The pod execution role trusts this cluster's Fargate profiles only."
  }
}

run "bring_your_own_node_role" {
  command = plan

  variables {
    iam_role    = { create = false, arn = "arn:aws:iam::123456789012:role/shared-nodes" }
    node_groups = { general = { instance_types = ["m7i.large"] } }
  }

  assert {
    condition     = length(module.node_role) == 0 && aws_eks_node_group.this["general"].node_role_arn == "arn:aws:iam::123456789012:role/shared-nodes" && output.node_role_name == null
    error_message = "A caller role replaces the node role."
  }
}

run "extend_the_node_role" {
  command = plan

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "ReadConfig", actions = ["ssm:GetParameter"], resources = ["arn:aws:ssm:eu-west-1:123456789012:parameter/nodes/*"] }]
    }
    node_groups = { general = { instance_types = ["m7i.large"] } }
  }

  assert {
    condition     = [for s in jsondecode(module.node_role[0].policy_json).Statement : s.Sid] == ["ReadConfig"]
    error_message = "Caller statements go to the node role."
  }
}

run "rejects_al2_ami_type" {
  command = plan

  variables {
    node_groups = {
      general = { instance_types = ["m7g.large"], ami_type = "AL2_ARM_64" }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Apps_Cluster"
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

run "rejects_invalid_cluster_version" {
  command = plan

  variables {
    cluster_version = "latest"
  }

  expect_failures = [var.cluster_version]
}

run "rejects_invalid_support_type" {
  command = plan

  variables {
    upgrade_support_type = "LTS"
  }

  expect_failures = [var.upgrade_support_type]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_open_public_endpoint" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "rejects_open_api_ingress" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_invalid_access_entry_type" {
  command = plan

  variables {
    access_entries = { x = { principal_arn = "arn:aws:iam::123456789012:role/x", type = "ADMIN" } }
  }

  expect_failures = [var.access_entries]
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
    kms = { key_id = "alias/eks" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_log_type" {
  command = plan

  variables {
    cloudwatch_logs = { log_types = ["kubelet"] }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_node_group_key" {
  command = plan

  variables {
    node_groups = { General_Pool = { instance_types = ["m7i.large"] } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_capacity_type" {
  command = plan

  variables {
    node_groups = { general = { instance_types = ["m7i.large"], capacity_type = "RESERVED" } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_sizes" {
  command = plan

  variables {
    node_groups = { general = { instance_types = ["m7i.large"], min_size = 4, max_size = 2 } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_taint" {
  command = plan

  variables {
    node_groups = { general = { instance_types = ["m7i.large"], taints = [{ key = "x", effect = "NoSchedule" }] } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_no_instance_types" {
  command = plan

  variables {
    node_groups = { general = { instance_types = [] } }
  }

  expect_failures = [var.node_groups]
}

run "rejects_invalid_fargate_key" {
  command = plan

  variables {
    fargate_profiles = { Jobs = { selectors = [{ namespace = "jobs" }] } }
  }

  expect_failures = [var.fargate_profiles]
}

run "rejects_fargate_without_selector" {
  command = plan

  variables {
    fargate_profiles = { jobs = { selectors = [] } }
  }

  expect_failures = [var.fargate_profiles]
}

run "rejects_unknown_addon" {
  command = plan

  variables {
    addons = { versions = { istio = "1.0" } }
  }

  expect_failures = [var.addons]
}

run "rejects_invalid_bucket_arn" {
  command = plan

  variables {
    addons = { s3_csi_bucket_arns = ["arn:aws:s3:::models/*"] }
  }

  expect_failures = [var.addons]
}

run "rejects_invalid_pod_identity_key" {
  command = plan

  variables {
    pod_identities = { Orders = { namespace = "orders", service_account = "api", role_arn = "arn:aws:iam::123456789012:role/x" } }
  }

  expect_failures = [var.pod_identities]
}

run "rejects_pod_identity_with_role_and_statements" {
  command = plan

  variables {
    pod_identities = {
      orders = {
        namespace         = "orders"
        service_account   = "api"
        role_arn          = "arn:aws:iam::123456789012:role/x"
        policy_statements = [{ actions = ["s3:GetObject"], resources = ["arn:aws:s3:::x/*"] }]
      }
    }
  }

  expect_failures = [var.pod_identities]
}
