module "fn_eu" {
  source = "../../../modules/aws/compute/lambda"

  application = "shop"
  environment = "prod"
  name        = "orders"
}

module "fn_us" {
  source = "../../../modules/aws/compute/lambda"
  providers = {
    aws = aws.us_east_1
  }

  application = "shop"
  environment = "prod"
  name        = "orders"
}

module "bucket_eu" {
  source = "../../../modules/aws/storage/s3"

  application = "shop"
  environment = "prod"
  name        = "assets"
}

module "bucket_us" {
  source = "../../../modules/aws/storage/s3"
  providers = {
    aws = aws.us_east_1
  }

  application = "shop"
  environment = "prod"
  name        = "assets"
}
