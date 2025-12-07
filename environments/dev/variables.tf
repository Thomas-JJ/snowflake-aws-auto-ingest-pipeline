variable "environment"                { type = string }
variable "aws_region"                  { type = string }

variable "snowflake_account_name" { type = string}
variable "snowflake_organization_name" { type = string}
variable "snowflake_role" { type = string}
variable "snowflake_user" { type = string}
variable "snowflake_warehouse" { type = string }

variable "gluejobs"{
    type = map(object({
        name = string
        source_bucket = string
        source_prefix = string

        target_bucket = string
        target_prefix = string

        script = string

        # Optional cron style schedule for Glue trigger (if you still want cron)
        cron_schedule              = optional(string)

        # New toggle: if true, create EventBridge rule and target for S3 event trigger
        event_trigger_enabled = optional(bool, false)

    }))
}


variable "database_name" { type = string }

variable "warehouse" {type = string }

variable "snowflake_admin_role" { type = string }

variable "snowflake_aws_principal_arn" { type = string }

variable "snowflake_external_id" { type = string }

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
