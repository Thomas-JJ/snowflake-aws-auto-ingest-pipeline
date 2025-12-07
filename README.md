# ❄️ Snowflake AWS Auto-Ingest Data Pipeline

> An event-driven ETL pipeline that automatically processes files from Amazon S3 into Snowflake with near real-time ingestion and change tracking.

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-purple?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EventBridge%20%7C%20Glue%20%7C%20S3-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Snowflake](https://img.shields.io/badge/Snowflake-Streams%20%7C%20Tasks-blue?logo=snowflake)](https://www.snowflake.com/)

---

## 🎯 Overview

This project implements a fully automated, event-driven data pipeline that moves raw files from Amazon S3 into Snowflake, processes them through a staged architecture, and delivers clean, merged records into analytical tables. The pipeline leverages AWS EventBridge, Glue, S3, SQS, and Snowflake Streams and Tasks to create a reliable, scalable ingestion workflow.

## 🏗️ Architecture

```
┌─────────────┐
│   S3 Raw    │  1. File arrives
│   Bucket    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ EventBridge │  2. Triggers Glue Workflow
│    Rule     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Glue Job   │  3. Transform & Process
│ (Transform) │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  S3 Stage   │  4. Processed file lands
│   Bucket    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│     SQS     │  5. S3 notification sent
│    Queue    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Snowpipe   │  6. Auto-ingest to staging
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Stream    │  7. Track new rows
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Task     │  8. Merge into target table
└─────────────┘
```

### Pipeline Flow

1. **File Arrival** → A new file is dropped into a configured S3 prefix, triggering an EventBridge rule
2. **Glue Processing** → EventBridge starts a Glue workflow that reads, transforms, and writes processed files to a target S3 location
3. **S3 Notification** → The processed file landing triggers an SQS notification
4. **Snowpipe Ingestion** → Snowflake listens to the SQS queue and auto-ingests files into a staging table in near real-time
5. **Stream Tracking** → A Snowflake Stream captures all new rows loaded into the staging table
6. **Task Execution** → A scheduled Snowflake Task runs a stored procedure to merge new rows into the target analytical table

## ✨ Features

- **🚀 Event-Driven Automation** - EventBridge triggers eliminate manual intervention
- **🔄 Glue Workflows** - Flexible file transformation and processing
- **📬 SQS Integration** - Reliable message queuing for Snowflake auto-ingest
- **📋 Configurable File Formats** - Support for CSV, JSON, Parquet, and more
- **🌊 Stream-Based Change Capture** - Track incremental changes efficiently
- **⏰ Task-Based Processing** - Scheduled merges with customizable intervals
- **🎛️ Fully Parameterized** - Terraform variables for easy configuration
- **🌍 Environment Aware** - Separate deployments for dev, staging, and production

## 📁 Repository Structure

```
.
├── main.tf                      # Main Terraform configuration
├── variables.tf                 # Variable definitions
├── terraform.tfvars.example     # Example variable values
├── glue_jobs/
│   └── scripts/                 # Glue ETL scripts (Python/PySpark)
├── snowflake/
│   ├── stages/                  # External stage definitions
│   ├── pipes/                   # Snowpipe configurations
│   ├── streams/                 # Stream definitions
│   ├── tasks/                   # Task schedules
│   └── procedures/              # Stored procedures for MERGE logic
└── README.md
```

## ⚙️ Configuration

### Environment Variables

```hcl
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
}
```

### Snowflake Connection

```hcl
variable "snowflake_account_name" {
  type = string
}

variable "snowflake_organization_name" {
  type = string
}

variable "snowflake_role" {
  description = "Role for pipeline operations"
  type        = string
}

variable "snowflake_user" {
  type = string
}

variable "snowflake_warehouse" {
  description = "Warehouse for task execution"
  type        = string
}

variable "snowflake_admin_role" {
  description = "Admin role for resource creation"
  type        = string
}

variable "snowflake_aws_principal_arn" {
  description = "AWS IAM role ARN for Snowflake access"
  type        = string
}

variable "snowflake_external_id" {
  description = "External ID for secure cross-account access"
  type        = string
}
```

### Glue Job Configuration

```hcl
variable "gluejobs" {
  description = "Map of Glue job configurations"
  type = map(object({
    name                   = string
    source_bucket          = string
    source_prefix          = string
    target_bucket          = string
    target_prefix          = string
    script                 = string
    cron_schedule          = optional(string)
    event_trigger_enabled  = optional(bool, false)
  }))
}
```

**Note:** Each Glue job can run on a cron schedule or be triggered by S3 events through EventBridge.

### Pipeline Definitions

```hcl
variable "pipelines" {
  description = "Pipeline configuration keyed by name"
  type = map(object({
    schema_name        = string
    staging_schema     = string
    source_bucket      = string
    source_prefix      = string
    
    file_format = object({
      type                        = string
      delimiter                   = optional(string, ",")
      skip_header                 = optional(number, 1)
      field_optionally_enclosed_by = optional(string, "\"")
      trim_space                  = optional(bool, true)
      date_format                 = optional(string, "YYYY-MM-DD")
    })
    
    target_table       = string
    staging_table      = string
    merge_keys         = list(string)
    cron_schedule      = string
    on_error           = optional(string, "ABORT_STATEMENT")
    pattern            = optional(string)
    procedure_name     = string
    procedure_lang     = string
    procedure_file     = string
  }))
}
```

This object drives all Snowflake resources for each pipeline: stages, pipes, streams, tasks, and stored procedures.

## 🚀 Deployment

### Prerequisites

- Terraform 1.0+
- AWS CLI configured with appropriate credentials
- Snowflake account with necessary permissions
- S3 buckets for raw and processed data

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/Thomas-JJ/snowflake-aws-auto-ingest-pipeline.git
   cd snowflake-aws-auto-ingest-pipeline
   ```

2. **Configure variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Review the plan**
   ```bash
   terraform plan
   ```

5. **Deploy**
   ```bash
   terraform apply
   ```

## 📊 Example Flow

Let's walk through a real example:

1. **File Upload** → `orders_2024_01_15.csv` lands in `s3://my-bucket/raw/orders/`
2. **Event Trigger** → EventBridge detects the new file and triggers the Glue workflow
3. **Transformation** → Glue job processes the file (cleaning, enrichment, validation)
4. **Output** → Transformed data written to `s3://my-bucket/stage/orders/orders_2024_01_15.parquet`
5. **SQS Notification** → S3 event pushes a message to the configured SQS queue
6. **Snowpipe Load** → Snowpipe ingests the file into `STAGING.ORDERS_STG` table
7. **Stream Detection** → Stream captures the newly inserted rows
8. **Scheduled Merge** → Task executes the stored procedure: `CALL merge_orders_proc()`
9. **Final Result** → Clean, deduplicated data available in `ANALYTICS.ORDERS`

## 🔮 Future Enhancements

- [ ] **AWS Step Functions** - Extended orchestration for complex workflows
- [ ] **SNS Notifications** - Real-time alerts for pipeline failures
- [ ] **Resource Monitors** - Snowflake warehouse optimization and cost tracking
- [ ] **Data Quality Checks** - Great Expectations or dbt integration
- [ ] **Dashboard Integration** - Power BI or Tableau connection examples
- [ ] **CI/CD Pipeline** - GitHub Actions for automated testing and deployment
- [ ] **Data Lineage** - Integration with data catalog tools
- [ ] **Monitoring & Observability** - CloudWatch dashboards and custom metrics

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📧 Contact

For questions or support, please open an issue in the GitHub repository.

---

**Built with ❤️ using Terraform, AWS, and Snowflake*