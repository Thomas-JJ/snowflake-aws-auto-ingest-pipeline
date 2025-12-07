variable "database_name" {
  description = "Full database name (passed from infrastrcture)"
  type        = string
}

variable "environment" {
  description = "Environment label (dev, staging, prod)"
  type        = string
}

variable "warehouse" {
  description = "Warehouse to run COPY/MERGE tasks"
  type        = string
}

variable "snowflake_admin_role" {
  description = "Admin role used for object creation"
  type        = string
}

variable "snowflake_aws_principal_arn" {
  type        = string
}

variable "snowflake_external_id" {
  type        = string
}

variable "pipelines" {
  description = "Pipeline configuration keyed by name"
  type = map(object({
    schema_name    = string
    staging_schema = string
    source_bucket  = string
    source_prefix  = string
    file_format = object({
      type                         = string
      delimiter                    = optional(string, ",")
      skip_header                  = optional(number, 1)
      field_optionally_enclosed_by = optional(string, "\"")
      trim_space                   = optional(bool, true)
      date_format                  = optional(string, "YYYY-MM-DD")
    })
    target_table   = string
    staging_table  = string
    merge_keys     = list(string)
    cron_schedule        = string
    on_error       = optional(string, "ABORT_STATEMENT")
    pattern        = optional(string)
    procedure_name = string
    procedure_lang = string
    procedure_file = string
  }))
}
