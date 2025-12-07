# snowflake-aws-auto-ingest-pipeline
Automatically processes files in AWS s3 to Snowflake.
Snowflake AWS Auto Ingest Data Pipeline

This project is an event driven ETL pipeline that moves raw files from Amazon S3 into Snowflake, processes them through a staged architecture, and delivers clean, merged records into analytical tables. The pipeline uses AWS EventBridge, Glue, S3, SQS, and Snowflake Streams and Tasks to create a reliable, automated ingestion workflow.

High Level Architecture

File arrives in S3
A new file dropped into a configured S3 prefix triggers an EventBridge rule.

EventBridge triggers a Glue Workflow
The workflow starts a Glue job that reads, transforms, and writes processed output files to a target S3 bucket and prefix.

Processed file lands in S3
The target S3 bucket is configured with an SQS notification. Snowflake listens to this SQS queue to auto ingest new files.

Snowflake loads data into a stage table
A Snowpipe uses the SQS notification channel to load the file into a staging table in near real time.

Changes captured in a Stream
A Snowflake Stream tracks new rows that were loaded into the staging table.

A Snowflake Task processes the Stream
On a defined schedule, a Snowflake Task runs a stored procedure that merges the new rows into a target base table.

This creates a continuous ingestion pipeline where every new file triggers automated processing end to end.

Features

• Event driven automation with EventBridge
• Glue workflows for file transformation
• SQS integration with Snowflake for auto ingest
• Configurable file format definitions
• Stream based change capture
• Task based merge processing
• Fully parameterized with Terraform variables
• Environment aware deployment (dev, prod, etc.)

Repository Structure
.
├── main.tf
├── variables.tf
├── glue_jobs/
│   └── scripts/
├── snowflake/
│   ├── stages/
│   ├── pipes/
│   ├── streams/
│   ├── tasks/
│   └── procedures/
└── README.md


Your layout may vary, but this provides a typical structure for Terraform plus AWS and Snowflake SQL artifacts.

Configuration Variables

Below are the key variables used to configure the deployment.

General Environment Variables
variable "environment" { type = string }
variable "aws_region"  { type = string }

Snowflake Connection Variables
variable "snowflake_account_name"     { type = string }
variable "snowflake_organization_name" { type = string }
variable "snowflake_role"             { type = string }
variable "snowflake_user"             { type = string }
variable "snowflake_warehouse"        { type = string }
variable "snowflake_admin_role"       { type = string }
variable "snowflake_aws_principal_arn" { type = string }
variable "snowflake_external_id"       { type = string }

Glue Job Configuration
variable "gluejobs" {
  type = map(object({
    name            = string
    source_bucket   = string
    source_prefix   = string
    target_bucket   = string
    target_prefix   = string
    script          = string
    cron_schedule   = optional(string)
    event_trigger_enabled = optional(bool, false)
  }))
}


Each Glue job can run on a schedule or be triggered by an S3 event through EventBridge.

Pipeline Definitions
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
    cron_schedule  = string
    on_error       = optional(string, "ABORT_STATEMENT")
    pattern        = optional(string)
    procedure_name = string
    procedure_lang = string
    procedure_file = string
  }))
}


This object drives all Snowflake objects for each pipeline, including stages, pipes, streams, tasks, and stored procedures.

Deployment

Set values in terraform.tfvars for your environment.

Run terraform init.

Run terraform plan.

Run terraform apply to deploy AWS and Snowflake resources.

Example Flow

File arrives in s3://my-bucket/raw/orders/

EventBridge fires and triggers the Glue workflow

Glue transforms the file and outputs to s3://my-bucket/stage/orders/

S3 event pushes a message to SQS

Snowpipe loads the file into STAGING.ORDERS_STG

Stream detects new rows

Task runs the merge into ANALYTICS.ORDERS

Future Enhancements

• Add Step Functions for extended orchestration
• Add SNS notifications for failures
• Add resource monitors and warehouse optimization
• Add Power BI or dashboard integration examples
• Include CI/CD with GitHub Actions
