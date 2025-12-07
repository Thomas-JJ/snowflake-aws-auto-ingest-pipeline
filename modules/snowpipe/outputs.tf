output "storage_integration_name" {
  value = snowflake_storage_integration.s3.name
}

output "stage_names" {
  value = { for k, v in snowflake_stage.s3 : k => v.name }
}

