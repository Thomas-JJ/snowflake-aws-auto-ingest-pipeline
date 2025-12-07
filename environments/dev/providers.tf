terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.11.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.10"
    }
  }
}

provider "aws" {}

provider "snowflake" {

  preview_features_enabled = [
    "snowflake_table_resource",
    "snowflake_table_constraint_resource",
    "snowflake_storage_integration_resource",
    "snowflake_file_format_resource",
    "snowflake_stage_resource",
    "snowflake_procedure_sql_resource",
    "snowflake_dynamic_table_resource",
    "snowflake_pipe_resource"
  ]

    account_name       = var.snowflake_account_name     # e.g. "xy12345" or "xy12345.us-east-1.aws"
    organization_name =  var.snowflake_organization_name

    user          = var.snowflake_user
    role          = var.snowflake_role

    warehouse   = var.snowflake_warehouse

    authenticator = "SNOWFLAKE_JWT"
}
