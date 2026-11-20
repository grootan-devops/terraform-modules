module "fn_eu" {
  source = "../../../modules/aws/compute/lambda"

  application = "shop"
  environment = "prod"
  name        = "orders"

  alarms = { topic_arns = module.alarm_routing.topic_arns["eu-west-1"] }
}

module "fn_us" {
  source = "../../../modules/aws/compute/lambda"
  providers = {
    aws = aws.us_east_1
  }

  application = "shop"
  environment = "prod"
  name        = "orders"

  alarms = { topic_arns = module.alarm_routing.topic_arns["us-east-1"] }
}

module "bucket_eu" {
  source = "../../../modules/aws/storage/s3"

  application = "shop"
  environment = "prod"
  name        = "assets"

  alarms = { topic_arns = module.alarm_routing.topic_arns["eu-west-1"] }
}

module "bucket_us" {
  source = "../../../modules/aws/storage/s3"
  providers = {
    aws = aws.us_east_1
  }

  application = "shop"
  environment = "prod"
  name        = "assets"

  alarms = { topic_arns = module.alarm_routing.topic_arns["us-east-1"] }
}
