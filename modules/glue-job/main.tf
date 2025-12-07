# S3 Buckets

data "aws_s3_bucket" "glue_scripts" {
  bucket = "aws-glue-assets-209479261794-us-east-2"  # Replace with your actual bucket name
}

# Upload Glue script to S3
resource "aws_s3_object" "glue_script" {
  for_each = var.gluejobs

  bucket = data.aws_s3_bucket.glue_scripts.id
  key    = each.value.script
  source = "../../modules/glue-job/scripts-py/${each.value.script}"
  etag   = filemd5("../../modules/glue-job/scripts-py/${each.value.script}")
}

# IAM Role for Glue Job
resource "aws_iam_role" "glue_role" {
  for_each = var.gluejobs

  name = "${each.value.name}-${var.environment}-glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for Glue
resource "aws_iam_role_policy_attachment" "glue_service" {
  for_each = var.gluejobs

  role       = aws_iam_role.glue_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "glue_s3_policy" {
  for_each = var.gluejobs

  name = "${each.value.name}-${var.environment}-glue-s3-access"
  role = aws_iam_role.glue_role[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${each.value.source_bucket}",
          "arn:aws:s3:::${each.value.source_bucket}/${each.value.source_prefix}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${each.value.target_bucket}/${each.value.target_prefix}*"
        ]
      }
    ]
  })
}

# Glue Job
resource "aws_glue_job" "transform_job" {
  for_each = var.gluejobs

  name     = "${each.value.name}-${var.environment}"
  role_arn = aws_iam_role.glue_role[each.key].arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.glue_scripts.id}/${each.value.script}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${data.aws_s3_bucket.glue_scripts.id}/spark-logs/"
    "--SOURCE_BUCKET"                    = each.value.source_bucket
    "--SOURCE_PREFIX"                    = each.value.source_prefix
    "--TARGET_BUCKET"                    = each.value.target_bucket
    "--TARGET_PREFIX"                    = each.value.target_prefix
  }

  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 60

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Environment = var.environment
    Purpose     = "data-transformation"
  }
}

# Glue Workflow
resource "aws_glue_workflow" "glue_workflow" {
  for_each = {
    for k, v in var.gluejobs :
    k => v
    if try(v.event_trigger_enabled, false)
  }

  name = "${each.value.name}-${var.environment}-workflow"

  description = "Workflow for ${each.value.name} in ${var.environment}"
  tags = {
    Environment = var.environment
  }
}

# Optional: Glue Trigger to run on schedule (if you still want cron-based runs)
resource "aws_glue_trigger" "schedule" {
  for_each = { for k, v in var.gluejobs : k => v if try(v.schedule, null) != null }

  name     = "${each.value.name}-${var.environment}-schedule"
  type     = "SCHEDULED"
  schedule = each.value.schedule

  actions {
    job_name = aws_glue_job.transform_job[each.key].name
  }
}

# Glue Trigger: root node in the workflow, fired when StartWorkflowRun is called
resource "aws_glue_trigger" "event" {
  for_each = {
    for k, v in var.gluejobs :
    k => v
    if try(v.event_trigger_enabled, false)
  }

  name          = "${each.value.name}-${var.environment}-event-trigger"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.glue_workflow[each.key].name

  actions {
    job_name = aws_glue_job.transform_job[each.key].name
  }
}

#--------------For event bridge-------------------
data "aws_caller_identity" "current" {}

# EventBridge rule: one per glue job
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  for_each = var.gluejobs

  name        = "${each.value.name}-${var.environment}-s3-object-created"
  description = "Trigger Glue job when new object is created in ${each.value.source_bucket}/${each.value.source_prefix}"

  event_pattern = jsonencode({
    "source"      : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : {
        "name" : [each.value.source_bucket]
      },
      "object" : {
        # match prefix if you only want objects under a specific folder
        "key" : [
          {
            "prefix" : each.value.source_prefix
          }
        ]
      }
    }
  })
}

resource "aws_iam_role" "eventbridge_glue_workflow" {
  name = "eventbridge-glue-workflow-${var.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_glue_workflow" {
  for_each = {
    for k, v in var.gluejobs :
    k => v
    if try(v.event_trigger_enabled, false)
  }

  name = "eventbridge-glue-workflow-${var.environment}-${each.key}-policy"
  role = aws_iam_role.eventbridge_glue_workflow.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
            "Sid": "ActionsForResource",
            "Effect": "Allow",
            "Action": [
                "glue:NotifyEvent"
            ],
            "Resource": [
                "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workflow/${aws_glue_workflow.glue_workflow[each.key].name}"
            ]
        }
    ]
  })
}

resource "aws_cloudwatch_event_target" "workflow_target" {
  for_each = {
    for k, v in var.gluejobs :
    k => v
    if try(v.event_trigger_enabled, false)
  }

  rule      = aws_cloudwatch_event_rule.s3_object_created[each.key].name
  target_id = "${each.value.name}-${var.environment}-workflow-target"

  # EventBridge supports Glue workflow as a target
  arn      = aws_glue_workflow.glue_workflow[each.key].arn
  role_arn = aws_iam_role.eventbridge_glue_workflow.arn

  # Optional: you can also use input or input_transformer here if you want
  # to pass event data into the workflow and then into the job via arguments.

  depends_on = [ aws_iam_role.eventbridge_glue_workflow, aws_cloudwatch_event_rule.s3_object_created ]

}


