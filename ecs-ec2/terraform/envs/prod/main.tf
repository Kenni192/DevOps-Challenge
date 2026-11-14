provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "network" {
  source               = "../../modules/network"
  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = [cidrsubnet(var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1)]
  private_subnet_cidrs = [cidrsubnet(var.vpc_cidr, 8, 10), cidrsubnet(var.vpc_cidr, 8, 11)]
}

module "ecr" {
  source = "../../modules/ecr"
  name   = local.name
}

module "alb" {
  source            = "../../modules/alb"
  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  container_port    = var.container_port
  target_type       = "instance"
}

module "ecs" {
  source                = "../../modules/ecs"
  name                  = local.name
  aws_region            = var.aws_region
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  image                 = "${module.ecr.repository_url}:${var.image_tag}"
  container_port        = var.container_port
  instance_type         = var.instance_type
  environment_variables = { ENVIRONMENT = var.environment, APP_VERSION = var.image_tag }

  # The target group must be attached to the ALB listener before the service can register with it.
  depends_on = [module.alb]
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  name                    = local.name
  aws_region              = var.aws_region
  cluster_name            = module.ecs.cluster_name
  service_name            = module.ecs.service_name
  log_group_name          = module.ecs.log_group_name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  alarm_email             = var.alarm_email
}
