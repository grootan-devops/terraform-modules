locals {
  region = coalesce(var.region, data.aws_region.current.region)
  base   = join("-", compact([var.application, var.environment, var.name]))

  full_names = {
    for key, spec in var.names : key => join("-", compact(concat(
      [local.base, spec.suffix],
      spec.uniqueness == "account" ? [local.region] : [],
      spec.uniqueness == "global" ? [data.aws_caller_identity.current.account_id, local.region] : []
    )))
  }

  names = {
    for key, full in local.full_names : key => (
      length(full) <= var.names[key].max_length ? full : "${trimsuffix(substr(full, 0, var.names[key].max_length - 7), "-")}-${substr(md5(full), 0, 6)}"
    )
  }

  governance_tags = {
    Application = var.application
    Environment = var.environment
    Name        = local.base
    ManagedBy   = "Terraform"
  }

  tags = merge(var.tags, local.governance_tags)
}
