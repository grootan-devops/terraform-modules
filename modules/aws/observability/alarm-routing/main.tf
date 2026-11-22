module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names       = { for s in distinct(var.severities) : s => { suffix = s, max_length = 256 } }
}

module "encryption" {
  source   = "../../core/encryption"
  for_each = toset(local.regions)

  application        = var.application
  environment        = var.environment
  purpose            = "sns"
  tags               = var.tags
  region             = each.key
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_sns_topic" "this" {
  for_each = local.topics

  region            = each.value.region
  name              = each.value.name
  display_name      = substr(each.value.name, 0, 100)
  kms_master_key_id = module.encryption[each.value.region].key_arn
  signature_version = 2

  tags = merge(module.naming.tags, { Name = each.value.name })

  lifecycle {
    precondition {
      condition     = split(":", module.encryption[each.value.region].key_arn)[3] == each.value.region
      error_message = "kms.key_id: a key in the topic Region."
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  for_each = local.topics

  region = each.value.region
  arn    = aws_sns_topic.this[each.key].arn
  policy = local.topic_policies[each.key]
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.email_subscriptions

  region         = each.value.region
  topic_arn      = aws_sns_topic.this[each.value.topic_key].arn
  protocol       = "email"
  endpoint       = each.value.address
  redrive_policy = try(local.redrive_policies[each.value.region], null)
}

resource "aws_sns_topic_subscription" "https" {
  for_each = local.https_subscriptions

  region                          = each.value.region
  topic_arn                       = aws_sns_topic.this[each.value.topic_key].arn
  protocol                        = "https"
  endpoint                        = var.https_subscriptions[each.value.severity][each.value.index].url
  raw_message_delivery            = nonsensitive(var.https_subscriptions[each.value.severity][each.value.index].raw_message_delivery)
  endpoint_auto_confirms          = nonsensitive(var.https_subscriptions[each.value.severity][each.value.index].endpoint_auto_confirms)
  confirmation_timeout_in_minutes = nonsensitive(var.https_subscriptions[each.value.severity][each.value.index].confirmation_timeout_in_minutes)
  delivery_policy                 = local.https_delivery_policy
  redrive_policy                  = try(local.redrive_policies[each.value.region], null)
}
