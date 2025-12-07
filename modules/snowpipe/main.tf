locals {
  env        = upper(var.environment)
  suffix     = upper(local.env)
  db_name    = upper("${var.database_name}_${var.environment}")
  allowed_locations = [
    for p in var.pipelines :
    "s3://${p.source_bucket}/${p.source_prefix}"
  ]
  stg_schema = { for k,v in var.pipelines : k => coalesce(v.staging_schema, v.schema_name) }
  proc_is_sql = { for k,v in var.pipelines : k => (upper(v.procedure_lang) == "SQL") }
  warehouse   = var.warehouse
}

# ---------- AWS role trusted by Snowflake for S3 read ----------
data "aws_iam_policy_document" "assume_by_snowflake" {
  statement {
    #sid     = "TrustSnowflake"
    effect  = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.snowflake_aws_principal_arn]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.snowflake_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_s3_access" {
  name                 = "snowflake-s3-role-${lower(local.env)}"
  assume_role_policy   = data.aws_iam_policy_document.assume_by_snowflake.json
  description          = "Snowflake read-only S3 access (${lower(local.env)})"
  max_session_duration = 3600
}

# Aggregate S3 permissions for all pipeline prefixes
data "aws_iam_policy_document" "s3_read" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject"
    ]

    resources = flatten([
      for p in var.pipelines : [
        "arn:aws:s3:::${p.source_bucket}",
        "arn:aws:s3:::${p.source_bucket}/*"
      ]
    ])
  }
}

resource "aws_iam_policy" "s3_read" {
  name   = "snowflake-s3-read-only-${lower(local.env)}"
  policy = data.aws_iam_policy_document.s3_read.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.snowflake_s3_access.name
  policy_arn = aws_iam_policy.s3_read.arn
}

# ---------- Snowflake storage integration shared for all pipelines ----------
resource "snowflake_storage_integration" "s3" {
  name                 = "AWS_S3_INT_${upper(local.env)}"
  type                 = "EXTERNAL_STAGE"
  storage_provider     = "S3"
  storage_aws_role_arn = aws_iam_role.snowflake_s3_access.arn

  storage_allowed_locations = local.allowed_locations
  enabled                   = true
  comment                   = "Batch COPY integration limited to Dev prefixes"
}

# CSV File format - use the same schema
resource "snowflake_file_format" "csv" {
  for_each  = var.pipelines
  name      = "FF_${upper(each.key)}_${upper(local.env)}"
  database  = local.db_name
  schema    = each.value.schema_name
  format_type                  = "CSV"
  field_delimiter              = coalesce(each.value.file_format.delimiter, ",")
  field_optionally_enclosed_by = coalesce(each.value.file_format.field_optionally_enclosed_by, "'")
  trim_space                   = coalesce(each.value.file_format.trim_space, true)
  empty_field_as_null          = true
  null_if                      = ["", "NULL", "null"]
  parse_header                 = true
  date_format                  = coalesce(each.value.file_format.date_format, "YYYY-MM-DD")
  skip_byte_order_mark         = true

}

resource "snowflake_stage" "s3" {
  for_each = var.pipelines

  name                = "STG_${upper(each.key)}_${local.env}"
  database            = local.db_name
  schema              = each.value.schema_name
  url                 = "s3://${each.value.source_bucket}/${each.value.source_prefix}"
  storage_integration = snowflake_storage_integration.s3.name

  depends_on = [ snowflake_storage_integration.s3 ]
}

resource "snowflake_pipe" "snow_pipe" {
  for_each = var.pipelines

  name     = "${upper(each.key)}_${local.env}_PIPE"
  database = local.db_name
  schema   = each.value.schema_name 

  comment        = "Auto ingest files from s3://${each.value.source_bucket}/${each.value.source_prefix}"
  auto_ingest    = true

copy_statement = <<-SQL
  COPY INTO ${local.db_name}.${each.value.schema_name}.STG_${each.value.target_table}
  FROM @${local.db_name}.${each.value.schema_name}.${snowflake_stage.s3[each.key].name}
  FILE_FORMAT = (
    FORMAT_NAME = ${local.db_name}.${each.value.schema_name}.${snowflake_file_format.csv[each.key].name}
  )
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = 'CONTINUE'
SQL
  lifecycle {
    replace_triggered_by = [
      snowflake_stage.s3
    ]
  }

  depends_on = [ snowflake_file_format.csv, snowflake_stage.s3 ]
}

resource "snowflake_stream_on_table" "staging_stream" {
  for_each = var.pipelines

  database = local.db_name
  schema   = each.value.schema_name
  name     = "STG_${each.value.target_table}_STREAM"
  
  table           = "${local.db_name}.${each.value.schema_name}.STG_${each.value.target_table}"
  append_only        = "false"
  
  show_initial_rows  = "false"
  
  comment = "Stream for tracking new rows in STG_${each.value.target_table}"

}


# SQL-language procedures - this will be for Merge into base table
resource "snowflake_procedure_sql" "proc_sql" {
  for_each = { for k, v in var.pipelines : k => v if true } # all pipelines use SQL procs

  database   = local.db_name
  schema     = each.value.schema_name
  name       = each.value.procedure_name

  arguments {
    arg_name      = "DB_NAME"
    arg_data_type = "STRING"
  }

  arguments {
    arg_name      = "SCHEMA_NAME"
    arg_data_type = "STRING"
  }

  arguments {
    arg_name      = "TARGET_TABLE"
    arg_data_type = "STRING"
  }

  arguments {
    arg_name      = "SPROC_NAME"
    arg_data_type = "STRING"
  }

  return_type = "VARCHAR"
  execute_as  = "OWNER"

  # Reference the SQL script file per pipeline
  procedure_definition = file(each.value.procedure_file)

    depends_on = [ snowflake_stream_on_table.staging_stream ]
}


# Task to run cron job automatically
resource "snowflake_task" "run_sproc_task" {
  for_each = var.pipelines

  name      = "TASK_${upper(each.key)}_${local.env}"
  database  = local.db_name
  schema    = each.value.schema_name
  warehouse = var.warehouse
  
  # KEY: Only execute when stream has data
  when = "SYSTEM$STREAM_HAS_DATA('${each.value.schema_name}.STG_${each.value.target_table}_STREAM')"
  
  schedule {
    #using_cron = each.value.cron_schedule
    minutes = 10
  }

  sql_statement = format(
      "CALL %s.%s.%s('%s','%s','%s','%s');",
    local.db_name,
    each.value.schema_name,
    each.value.procedure_name,

    local.db_name,
    each.value.schema_name,
    each.value.target_table,

    each.value.procedure_name
  )

  started = true
  
  depends_on = [ snowflake_procedure_sql.proc_sql ]
}


# Add Notification to s3 bucket

locals {
  # 1. Unique list of buckets from all pipelines
  unique_buckets = toset([
    for p in var.pipelines : p.source_bucket
  ])

  # 2. Pipelines grouped by bucket
  pipelines_by_bucket = {
    for bucket in local.unique_buckets :
    bucket => [
      for name, p in var.pipelines :
      {
        key           = name
        source_prefix = p.source_prefix
      }
      if p.source_bucket == bucket
    ]
  }
}

data "aws_s3_bucket" "b" {
  for_each = local.pipelines_by_bucket
  bucket   = each.key
}

resource "aws_s3_bucket_notification" "snowpipe" {
  for_each = local.pipelines_by_bucket

  bucket = data.aws_s3_bucket.b[each.key].id
  eventbridge = true

  dynamic "queue" {
    for_each = each.value
    content {
      queue_arn     = snowflake_pipe.snow_pipe[queue.value.key].notification_channel
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = queue.value.source_prefix
    }
  }
  depends_on = [ snowflake_pipe.snow_pipe ]
}
