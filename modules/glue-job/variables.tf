
variable "environment" { type = string }


variable "aws_region" { type = string }

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
