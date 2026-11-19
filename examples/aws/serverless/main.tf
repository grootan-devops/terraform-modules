module "users" {
  source = "../../../modules/aws/security/cognito"

  application = var.application
  environment = var.environment
  name        = "users"
  clients = {
    web = {}
  }
}

module "orders_table" {
  source = "../../../modules/aws/database/dynamodb"

  application = var.application
  environment = var.environment
  name        = "orders"
  hash_key    = "order_id"
  stream      = { enabled = true }
  kms         = { create = true }

  alarms = { topic_arns = local.alarm_topics }
}

module "orders_queue" {
  source = "../../../modules/aws/integration/sqs"

  application = var.application
  environment = var.environment
  name        = "orders"
  kms         = { create = true }
  allowed_publishers = {
    events = { principal = "events.amazonaws.com", source_arn = module.events.rule_arns["order-created"] }
  }

  alarms = { topic_arns = local.alarm_topics }
}

module "api_fn" {
  source = "../../../modules/aws/compute/lambda"

  application           = var.application
  environment           = var.environment
  name                  = "api"
  environment_variables = { TABLE_NAME = module.orders_table.name }
  iam_role = {
    policy_statements = [
      { sid = "ReadWriteOrders", actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"], resources = [module.orders_table.arn] },
      { sid = "PublishEvents", actions = ["events:PutEvents"], resources = [module.events.bus_arn] }
    ]
  }

  alarms = { topic_arns = local.alarm_topics }
}

module "worker_fn" {
  source = "../../../modules/aws/compute/lambda"

  application = var.application
  environment = var.environment
  name        = "worker"
  event_sources = {
    orders = { type = "sqs", arn = module.orders_queue.arn, batch_size = 10, maximum_concurrency = 5 }
    audit  = { type = "dynamodb", arn = module.orders_table.stream_arn }
  }

  alarms = { topic_arns = local.alarm_topics }
}

module "events" {
  source = "../../../modules/aws/integration/eventbridge"

  application = var.application
  environment = var.environment
  name        = "orders"
  rules = {
    order-created = { event_pattern = jsonencode({ source = ["shop.orders"], "detail-type" = ["OrderCreated"] }) }
  }
  targets = {
    order-created = { queue = { type = "sqs", arn = module.orders_queue.arn, dead_letter_queue = { arn = module.orders_queue.dlq_arn } } }
  }
  scheduler = {
    enabled = true
    schedules = {
      nightly = {
        expression = "cron(0 2 * * ? *)"
        target = {
          type              = "lambda"
          arn               = module.worker_fn.alias_arn
          dead_letter_queue = { arn = module.orders_queue.dlq_arn, kms_key_arn = module.orders_queue.kms_key_arn }
        }
      }
    }
  }

  alarms = { topic_arns = local.alarm_topics }
}

module "api" {
  source = "../../../modules/aws/integration/api-gateway"

  application = var.application
  environment = var.environment
  authorizers = {
    users = { provider_arns = [module.users.arn] }
  }
  routes = {
    "/orders" = {
      methods = {
        GET  = { authorizer_key = "users", lambda = { invoke_arn = module.api_fn.invoke_arn, alias_arn = module.api_fn.alias_arn } }
        POST = { authorizer_key = "users", lambda = { invoke_arn = module.api_fn.invoke_arn, alias_arn = module.api_fn.alias_arn } }
      }
    }
  }

  alarms = { topic_arns = local.alarm_topics }
}

module "http_api" {
  source = "../../../modules/aws/integration/http-api"

  application = var.application
  environment = var.environment
  name        = "public"
  integrations = {
    orders = { type = "lambda", lambda = { function_arn = module.api_fn.alias_arn } }
  }
  authorizers = {
    users = { jwt = { issuer = "https://${module.users.endpoint}", audience = [module.users.client_ids["web"]] } }
  }
  routes = {
    "GET /orders"  = { integration = "orders", authorizer = "users" }
    "POST /orders" = { integration = "orders", authorizer = "users" }
  }

  alarms = { topic_arns = local.alarm_topics }
}
