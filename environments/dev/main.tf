
######################################
# Modules
######################################

# Glue Jobs

module "gluejob" {
  source      = "../../modules/glue-job"
  environment = var.environment

  aws_region = var.aws_region

  gluejobs = var.gluejobs

}

module "snowflake_pipelines" {
  source      = "../../modules/snowpipe"
  environment = var.environment

  snowflake_admin_role = var.snowflake_admin_role
  snowflake_aws_principal_arn = var.snowflake_aws_principal_arn
  snowflake_external_id = var.snowflake_external_id

  database_name = var.database_name
  warehouse = var.warehouse

  pipelines = var.pipelines

}