output "detector_ids" {
  description = "Detector ID by Region."
  value       = { for region, detector in aws_guardduty_detector.this : region => detector.id }
}

output "detector_arns" {
  description = "Detector ARN by Region."
  value       = { for region, detector in aws_guardduty_detector.this : region => detector.arn }
}

output "publishing_destination_ids" {
  description = "Findings export ID by Region."
  value       = { for region, destination in aws_guardduty_publishing_destination.this : region => destination.destination_id }
}

output "kms_key_arn" {
  description = "Findings export key ARN; null without an export."
  value       = local.export_enabled ? local.kms_key_arn : null
}

output "destination_policy_json" {
  description = "Bucket policy statements for the findings export; null without one."
  value       = local.export_enabled ? module.destination_policy.json : null
}

output "kms_key_policy_json" {
  description = "Key policy statement for the findings export; null without one."
  value       = local.export_enabled ? module.kms_policy.json : null
}
