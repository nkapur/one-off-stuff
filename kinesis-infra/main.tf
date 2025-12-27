# =============================================================================
# Kinesis Event Ingestion Infrastructure
# 
# This configuration demonstrates how to use the kinesis_event_flow module
# to incrementally add new event types/families.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "kinesis-events/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}


provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "kinesis-event-ingestion"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

data "aws_caller_identity" "current" {}

# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

# =============================================================================
# Event Stream Modules
# 
# Add new event types by creating additional module blocks below.
# Each module creates an isolated Kinesis stream with its own Lambda processor.
# =============================================================================

# Example: User Activity Events
module "user_activity_events" {
  source = "./modules/kinesis_event_flow"

  event_type  = "user_activity"
  environment = var.environment

  # Stream configuration
  shard_count      = 1
  retention_period = 24 # hours

  # Lambda processor configuration
  lambda_source_path = "${path.module}/lambda/user_activity"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 256
  lambda_timeout     = 30

  # Event source mapping (zero-scaling is automatic with Lambda)
  batch_size           = 100
  batch_window_seconds = 5
  starting_position    = "LATEST"

  # Error handling
  dlq_enabled            = true
  max_retry_attempts     = 3
  max_record_age_seconds = 3600

  # Optional: Pass custom environment variables
  lambda_environment_variables = {
    LOG_LEVEL = "INFO"
  }

  tags = {
    EventFamily = "user"
  }
}

# Example: Order Events
module "order_events" {
  source = "./modules/kinesis_event_flow"

  event_type  = "orders"
  environment = var.environment

  shard_count      = 2 # Higher throughput for orders
  retention_period = 48

  lambda_source_path = "${path.module}/lambda/orders"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 512
  lambda_timeout     = 60

  batch_size           = 50
  batch_window_seconds = 3
  starting_position    = "LATEST"

  dlq_enabled            = true
  max_retry_attempts     = 5
  max_record_age_seconds = 7200

  lambda_environment_variables = {
    LOG_LEVEL           = "INFO"
    ENABLE_ORDER_ALERTS = "true"
  }

  tags = {
    EventFamily = "commerce"
  }
}

# Example: Payment Events
module "payment_events" {
  source = "./modules/kinesis_event_flow"

  event_type  = "payments"
  environment = var.environment

  shard_count      = 2
  retention_period = 168 # 7 days for compliance

  lambda_source_path         = "${path.module}/lambda/payments"
  lambda_handler             = "handler.process_event"
  lambda_runtime             = "python3.11"
  lambda_memory_size         = 512
  lambda_timeout             = 30
  enable_enhanced_monitoring = true # Enhanced monitoring for payments

  batch_size           = 25 # Smaller batches for payment processing
  batch_window_seconds = 1
  starting_position    = "LATEST"

  dlq_enabled            = true
  max_retry_attempts     = 10    # More retries for critical payment events
  max_record_age_seconds = 14400 # 4 hours

  lambda_environment_variables = {
    LOG_LEVEL = "DEBUG"
  }

  tags = {
    EventFamily = "finance"
    Compliance  = "PCI-DSS"
  }
}

# =============================================================================
# API Gateway - Unified Entry Point for All Events
# =============================================================================

module "api_gateway" {
  source = "./modules/api_gateway"

  name        = "events-ingestion"
  environment = var.environment
  description = "Unified API Gateway for all event ingestion"

  # Register all event streams with the gateway
  event_streams = {
    user_activity = {
      stream_name = module.user_activity_events.stream_name
      stream_arn  = module.user_activity_events.stream_arn
      kms_key_arn = module.user_activity_events.kms_key_arn
    }
    orders = {
      stream_name = module.order_events.stream_name
      stream_arn  = module.order_events.stream_arn
      kms_key_arn = module.order_events.kms_key_arn
    }
    payments = {
      stream_name = module.payment_events.stream_name
      stream_arn  = module.payment_events.stream_arn
      kms_key_arn = module.payment_events.kms_key_arn
    }
  }

  stage_name = "v1"

  # Throttling
  throttling_burst_limit = 5000
  throttling_rate_limit  = 10000

  # Logging & Tracing
  enable_access_logging = true
  enable_xray_tracing   = var.environment == "prod"

  # Security
  api_key_required = false # Set to true for production

  # CORS
  cors_allowed_origins = ["*"] # Restrict in production
  cors_allowed_methods = ["POST", "OPTIONS"]

  tags = {
    Component = "ingestion-gateway"
  }
}

# =============================================================================
# Multi-Stream Consumer: Analytics Aggregator
# 
# This consumer reads from BOTH user_activity and payments streams,
# correlating data for analytics purposes.
# =============================================================================

locals {
  analytics_prefix = "${var.environment}-analytics-aggregator"
}

# Package the Lambda code
data "archive_file" "analytics_aggregator" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/analytics_aggregator"
  output_path = "${path.module}/.terraform/tmp/analytics-aggregator-lambda.zip"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "analytics_aggregator" {
  name              = "/aws/lambda/${local.analytics_prefix}"
  retention_in_days = 14
}

# IAM Role for the Lambda
resource "aws_iam_role" "analytics_aggregator" {
  name = "${local.analytics_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_aggregator_basic" {
  role       = aws_iam_role.analytics_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy to read from both Kinesis streams
resource "aws_iam_policy" "analytics_aggregator_kinesis" {
  name        = "${local.analytics_prefix}-kinesis-access"
  description = "Allow analytics aggregator to read from user_activity and payments streams"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = [
          module.user_activity_events.stream_arn,
          module.payment_events.stream_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          module.user_activity_events.kms_key_arn,
          module.payment_events.kms_key_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_aggregator_kinesis" {
  role       = aws_iam_role.analytics_aggregator.name
  policy_arn = aws_iam_policy.analytics_aggregator_kinesis.arn
}

# The Lambda Function
resource "aws_lambda_function" "analytics_aggregator" {
  function_name = local.analytics_prefix
  role          = aws_iam_role.analytics_aggregator.arn
  handler       = "handler.process_event"
  runtime       = "python3.11"

  filename         = data.archive_file.analytics_aggregator.output_path
  source_code_hash = data.archive_file.analytics_aggregator.output_base64sha256

  memory_size = 512
  timeout     = 60

  environment {
    variables = {
      LOG_LEVEL   = "INFO"
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.analytics_aggregator_basic,
    aws_iam_role_policy_attachment.analytics_aggregator_kinesis,
    aws_cloudwatch_log_group.analytics_aggregator
  ]
}

# Event Source Mapping: User Activity Stream -> Analytics Aggregator
resource "aws_lambda_event_source_mapping" "analytics_user_activity" {
  event_source_arn  = module.user_activity_events.stream_arn
  function_name     = aws_lambda_function.analytics_aggregator.arn
  starting_position = "LATEST"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 10
  parallelization_factor             = 1

  # Error handling
  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  depends_on = [
    aws_iam_role_policy_attachment.analytics_aggregator_kinesis
  ]
}

# Event Source Mapping: Payments Stream -> Analytics Aggregator
resource "aws_lambda_event_source_mapping" "analytics_payments" {
  event_source_arn  = module.payment_events.stream_arn
  function_name     = aws_lambda_function.analytics_aggregator.arn
  starting_position = "LATEST"

  batch_size                         = 50
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 1

  # Error handling
  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  depends_on = [
    aws_iam_role_policy_attachment.analytics_aggregator_kinesis
  ]
}

# =============================================================================
# Fraud Detector Consumer (Payments Stream)
# =============================================================================

locals {
  fraud_detector_prefix = "${var.environment}-fraud-detector"
}

data "archive_file" "fraud_detector" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/fraud_detector"
  output_path = "${path.module}/.terraform/tmp/fraud-detector-lambda.zip"
}

resource "aws_cloudwatch_log_group" "fraud_detector" {
  name              = "/aws/lambda/${local.fraud_detector_prefix}"
  retention_in_days = 14
}

resource "aws_iam_role" "fraud_detector" {
  name = "${local.fraud_detector_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fraud_detector_basic" {
  role       = aws_iam_role.fraud_detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "fraud_detector_kinesis" {
  name = "${local.fraud_detector_prefix}-kinesis-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards"
        ]
        Resource = [module.payment_events.stream_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.payment_events.kms_key_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fraud_detector_kinesis" {
  role       = aws_iam_role.fraud_detector.name
  policy_arn = aws_iam_policy.fraud_detector_kinesis.arn
}

resource "aws_lambda_function" "fraud_detector" {
  function_name = local.fraud_detector_prefix
  role          = aws_iam_role.fraud_detector.arn
  handler       = "handler.process_event"
  runtime       = "python3.11"

  filename         = data.archive_file.fraud_detector.output_path
  source_code_hash = data.archive_file.fraud_detector.output_base64sha256

  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      LOG_LEVEL   = "INFO"
      ENVIRONMENT = var.environment
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.fraud_detector_basic,
    aws_iam_role_policy_attachment.fraud_detector_kinesis,
    aws_cloudwatch_log_group.fraud_detector
  ]
}

resource "aws_lambda_event_source_mapping" "fraud_detector_payments" {
  event_source_arn  = module.payment_events.stream_arn
  function_name     = aws_lambda_function.fraud_detector.arn
  starting_position = "LATEST"

  batch_size                         = 10
  maximum_batching_window_in_seconds = 1
  parallelization_factor             = 1

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 1800
  bisect_batch_on_function_error = true

  depends_on = [aws_iam_role_policy_attachment.fraud_detector_kinesis]
}

# =============================================================================
# Outputs
# =============================================================================

output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = module.api_gateway.invoke_url
}

output "event_endpoints" {
  description = "Endpoints for each event type"
  value       = module.api_gateway.event_endpoints
}

output "user_activity_stream" {
  description = "User activity Kinesis stream details"
  value = {
    name    = module.user_activity_events.stream_name
    arn     = module.user_activity_events.stream_arn
    lambda  = module.user_activity_events.lambda_function_name
    dlq_url = module.user_activity_events.dlq_url
  }
}

output "order_stream" {
  description = "Orders Kinesis stream details"
  value = {
    name    = module.order_events.stream_name
    arn     = module.order_events.stream_arn
    lambda  = module.order_events.lambda_function_name
    dlq_url = module.order_events.dlq_url
  }
}

output "payment_stream" {
  description = "Payments Kinesis stream details"
  value = {
    name    = module.payment_events.stream_name
    arn     = module.payment_events.stream_arn
    lambda  = module.payment_events.lambda_function_name
    dlq_url = module.payment_events.dlq_url
  }
}

output "analytics_aggregator" {
  description = "Analytics aggregator (multi-stream consumer) details"
  value = {
    lambda_name = aws_lambda_function.analytics_aggregator.function_name
    lambda_arn  = aws_lambda_function.analytics_aggregator.arn
    source_streams = [
      module.user_activity_events.stream_name,
      module.payment_events.stream_name
    ]
  }
}

output "fraud_detector" {
  description = "Fraud detector consumer details"
  value = {
    lambda_name   = aws_lambda_function.fraud_detector.function_name
    lambda_arn    = aws_lambda_function.fraud_detector.arn
    source_stream = module.payment_events.stream_name
  }
}

