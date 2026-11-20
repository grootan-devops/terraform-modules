output "function_names" {
  description = "Function names per Region."
  value       = [module.fn_eu.name, module.fn_us.name]
}

output "role_names" {
  description = "Execution role names per Region."
  value       = [module.fn_eu.role_name, module.fn_us.role_name]
}

output "bucket_names" {
  description = "Bucket names per Region."
  value       = [module.bucket_eu.name, module.bucket_us.name]
}
