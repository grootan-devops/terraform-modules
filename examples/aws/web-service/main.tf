module "vpc" {
  source = "../../../modules/aws/network/vpc"

  application = var.application
  environment = var.environment
  cidr_block  = "10.20.0.0/16"
}

module "logs" {
  source = "../../../modules/aws/storage/log-bucket"

  application = var.application
  environment = var.environment
  name        = "logs"
  elb_logs    = { enabled = true }
}

module "zone" {
  source = "../../../modules/aws/network/route53"

  application = var.application
  environment = var.environment
  zone_name   = var.domain_name
  records = {
    web = { type = "A", alias = { name = module.alb.dns_name, zone_id = module.alb.zone_id, evaluate_target_health = true } }
  }
}

module "cert" {
  source = "../../../modules/aws/security/acm"

  application = var.application
  environment = var.environment
  domain_name = var.domain_name
  validation  = { zone_id = module.zone.zone_id }
}

module "alb" {
  source = "../../../modules/aws/network/alb"

  application          = var.application
  environment          = var.environment
  internal             = false
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.public_subnet_ids
  security_group       = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  https_listener       = { certificate_arn = module.cert.arn }
  target_groups        = { web = { port = 8080 } }
  default_target_group = "web"
  access_logs          = { enabled = true, bucket = module.logs.name }
}

module "private_link" {
  source = "../../../modules/aws/network/nlb"

  application = var.application
  environment = var.environment
  name        = "partners"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
  listeners   = { https = { port = 443, target_group = "alb" } }
  target_groups = {
    alb = { port = 443, target_type = "alb", health_check = { protocol = "HTTPS", path = "/" }, targets = { alb = { id = module.alb.arn } } }
  }
  security_group   = { egress_security_group_ids = [module.alb.security_group_id] }
  endpoint_service = { enabled = true, allowed_principals = [var.partner_principal_arn] }
}

module "db" {
  source = "../../../modules/aws/database/rds/postgres"

  application    = var.application
  environment    = var.environment
  name           = "orders"
  engine_version = "18"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  security_group = { ingress_security_group_ids = [module.app.security_group_id] }
  kms            = { create = true }
}

module "app" {
  source = "../../../modules/aws/compute/ecs"

  application              = var.application
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  readonly_root_filesystem = true
  security_group           = { ingress_security_group_ids = [module.alb.security_group_id] }
  services = {
    web = {
      image             = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/shop-web:1.0.0"
      container_port    = 8080
      target_group_arns = [module.alb.target_group_arns["web"]]
      writable_paths    = ["/tmp"]
      environment       = { DB_HOST = module.db.address, DB_PORT = tostring(module.db.port) }
      secrets           = { DB_CREDENTIALS = module.db.master_user_secret_arn }
    }
  }
}
