module "alarms" {
  source = "../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (module.naming.region) = var.alarms.topic_arns }
  }

  dynamodb_tables = {
    table = {
      table_name                   = aws_dynamodb_table.this.name
      global_secondary_index_names = sort(keys(var.global_secondary_indexes))
      alarms                       = var.alarms.overrides
    }
  }
}
