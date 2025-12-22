locals {
  deployment_mode = "dev"
  size = "large"
}

module "my_tiger_db" {
  source        = "../modules/tiger_data_db"
  instance_name = "${local.deployment_mode}-${local.size}-db"
  size          = local.size
  extensions    = [
    "postgis",
    "pg_stat_statements",
  ]
  deployment_mode = local.deployment_mode
}