output "member_associations" {
  description = "Member relationship status by account_id/region."
  value       = { for key, association in aws_inspector2_member_association.this : key => association.relationship_status }
}

output "filter_arns" {
  description = "Suppression rule ARNs by key, then Region."
  value = {
    for key in keys(var.filters) : key => {
      for instance_key, filter in aws_inspector2_filter.this : local.filter_instances[instance_key].region => filter.arn
      if local.filter_instances[instance_key].key == key
    }
    if local.org_enabled
  }
}
