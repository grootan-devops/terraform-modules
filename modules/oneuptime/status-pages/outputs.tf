output "status_page_ids" {
  description = "status page key -> status page id"
  value       = { for key, page in oneuptime_status_page.this : key => page.id }
}

output "status_page_group_ids" {
  description = "\"<page key>.<group key>\" -> status page group id"
  value       = { for key, group in oneuptime_status_page_group.this : key => group.id }
}
