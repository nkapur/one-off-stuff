# =============================================================================
# API Gateway Module - Variables
# Shared API Gateway that fronts all event ingestion
# =============================================================================

variable "name" {
  description = "Name for the API Gateway"
  type        = string
  default     = "events-ingestion"
}

variable "environment" {
  description = "Deployment environment (e.g., 'dev', 'staging', 'prod')"
  type        = string
  default     = "dev"
}

variable "description" {
  description = "Description for the API Gateway"
  type        = string
  default     = "Events ingestion API Gateway for Kinesis streams"
}

variable "event_streams" {
  description = "Map of event types to their Kinesis stream configurations"
  type = map(object({
    stream_name = string
    stream_arn  = string
    kms_key_arn = string
  }))
  default = {}
}

variable "stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "v1"
}

variable "throttling_burst_limit" {
  description = "API Gateway throttling burst limit"
  type        = number
  default     = 5000
}

variable "throttling_rate_limit" {
  description = "API Gateway throttling rate limit (requests per second)"
  type        = number
  default     = 10000
}

variable "enable_access_logging" {
  description = "Enable CloudWatch access logging"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = false
}

variable "api_key_required" {
  description = "Require API key for all requests"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed CORS methods"
  type        = list(string)
  default     = ["POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed CORS headers"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

