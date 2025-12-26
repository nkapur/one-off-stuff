# =============================================================================
# Kinesis Event Flow Module - Variables
# =============================================================================

variable "event_type" {
  description = "Name/identifier for the event type (e.g., 'user_activity', 'orders', 'payments')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.event_type))
    error_message = "Event type must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "environment" {
  description = "Deployment environment (e.g., 'dev', 'staging', 'prod')"
  type        = string
  default     = "dev"
}

variable "shard_count" {
  description = "Number of shards for the Kinesis stream"
  type        = number
  default     = 1
}

variable "retention_period" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 24

  validation {
    condition     = var.retention_period >= 24 && var.retention_period <= 8760
    error_message = "Retention period must be between 24 and 8760 hours."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime environment"
  type        = string
  default     = "python3.11"
}

variable "lambda_handler" {
  description = "Lambda function handler"
  type        = string
  default     = "handler.process_event"
}

variable "lambda_source_path" {
  description = "Path to the Lambda function source code directory"
  type        = string
}

variable "lambda_memory_size" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "batch_size" {
  description = "Maximum number of records to retrieve per batch from Kinesis"
  type        = number
  default     = 100
}

variable "batch_window_seconds" {
  description = "Maximum time to wait for batch to fill (enables batching window)"
  type        = number
  default     = 5
}

variable "parallelization_factor" {
  description = "Number of batches to process concurrently per shard"
  type        = number
  default     = 1

  validation {
    condition     = var.parallelization_factor >= 1 && var.parallelization_factor <= 10
    error_message = "Parallelization factor must be between 1 and 10."
  }
}

variable "starting_position" {
  description = "Position in the stream where Lambda starts reading (TRIM_HORIZON or LATEST)"
  type        = string
  default     = "LATEST"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.starting_position)
    error_message = "Starting position must be either TRIM_HORIZON or LATEST."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced (shard-level) CloudWatch metrics"
  type        = bool
  default     = false
}

variable "lambda_environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "lambda_vpc_config" {
  description = "VPC configuration for Lambda (optional)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "dlq_enabled" {
  description = "Enable Dead Letter Queue for failed records"
  type        = bool
  default     = true
}

variable "max_retry_attempts" {
  description = "Maximum number of retry attempts for failed records"
  type        = number
  default     = 3
}

variable "max_record_age_seconds" {
  description = "Maximum age of a record before it's discarded"
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

