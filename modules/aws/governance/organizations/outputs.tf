output "organization_id" {
  description = "Organization ID."
  value       = local.organization_id
}

output "root_id" {
  description = "Root ID the root target resolves to."
  value       = local.root_id
}

output "enabled_policy_types" {
  description = "Policy types enabled on the root."
  value       = sort(tolist(local.effective_policy_types))
}

output "policies" {
  description = "Policies by key: id, arn, name, type."
  value = { for k, p in aws_organizations_policy.this : k => {
    id   = p.id
    arn  = p.arn
    name = p.name
    type = p.type
  } }
}

output "attachments" {
  description = "Attachments by policy key and target: policy_id, target_id."
  value = { for k, a in aws_organizations_policy_attachment.this : k => {
    policy_id = a.policy_id
    target_id = a.target_id
  } }
}
