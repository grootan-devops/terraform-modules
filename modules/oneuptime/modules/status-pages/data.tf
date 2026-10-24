// Custom domains a status page is served on must already exist and be verified
// in the OneUptime project; this module only attaches them. Looked up once per
// unique domain name, however many pages reference it.
data "oneuptime_domain" "by_name" {
  for_each = local.status_page_domain_names
  name     = each.value
}
