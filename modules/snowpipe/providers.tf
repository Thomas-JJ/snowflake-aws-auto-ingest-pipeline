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