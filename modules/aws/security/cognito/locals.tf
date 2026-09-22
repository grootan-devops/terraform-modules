locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )

  default_read_attributes = [
    "address", "birthdate", "email", "email_verified", "family_name", "gender",
    "given_name", "locale", "middle_name", "name", "nickname", "phone_number",
    "phone_number_verified", "picture", "preferred_username", "profile",
    "updated_at", "website", "zoneinfo"
  ]

  default_write_attributes = [
    "address", "birthdate", "email", "family_name", "gender", "given_name",
    "locale", "middle_name", "name", "nickname", "phone_number",
    "picture", "preferred_username", "profile",
    "updated_at", "website", "zoneinfo"
  ]

  custom_attributes_names = [for attr in var.custom_schema_attributes : "custom:${attr.name}"]

  final_read_attributes  = concat(coalesce(var.read_attributes, local.default_read_attributes), local.custom_attributes_names)
  final_write_attributes = concat(coalesce(var.write_attributes, local.default_write_attributes), local.custom_attributes_names)
}
