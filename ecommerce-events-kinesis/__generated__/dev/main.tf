# =============================================================================
# Generated Kinesis Event Infrastructure - DEV
# Project: ecommerce-events-kinesis
# DO NOT EDIT - Regenerate with: python <platform>/generate.py config.yaml dev
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

  # Uncomment for remote state
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "ecommerce-events-kinesis/dev/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "ecommerce-events-kinesis"
      ManagedBy   = "terraform"
      Environment = "dev"
    }
  }
}

variable "environment" {
  default = "dev"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


# =============================================================================
# Stream + Processor: user_activity
# =============================================================================

module "user_activity_events" {
  source = "../../../kinesis-infra/modules/kinesis_event_flow"

  event_type  = "user_activity"
  environment = var.environment

  # Stream configuration
  shard_count              = 1
  retention_period         = 24
  enable_enhanced_monitoring = false

  # Lambda processor configuration
  lambda_source_path = "${path.module}/../../lambda/user_activity"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 256
  lambda_timeout     = 30

  # Event source mapping
  batch_size           = 100
  batch_window_seconds = 5
  starting_position    = "LATEST"

  # Error handling
  dlq_enabled            = true
  max_retry_attempts     = 3
  max_record_age_seconds = 3600

}


# =============================================================================
# Stream + Processor: orders
# =============================================================================

module "orders_events" {
  source = "../../../kinesis-infra/modules/kinesis_event_flow"

  event_type  = "orders"
  environment = var.environment

  # Stream configuration
  shard_count              = 2
  retention_period         = 48
  enable_enhanced_monitoring = false

  # Lambda processor configuration
  lambda_source_path = "${path.module}/../../lambda/orders"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 512
  lambda_timeout     = 60

  # Event source mapping
  batch_size           = 50
  batch_window_seconds = 5
  starting_position    = "LATEST"

  # Error handling
  dlq_enabled            = true
  max_retry_attempts     = 3
  max_record_age_seconds = 3600

  lambda_environment_variables = {
    ENABLE_ORDER_ALERTS = "true"
  }
}


# =============================================================================
# Stream + Processor: payments
# =============================================================================

module "payments_events" {
  source = "../../../kinesis-infra/modules/kinesis_event_flow"

  event_type  = "payments"
  environment = var.environment

  # Stream configuration
  shard_count              = 2
  retention_period         = 168
  enable_enhanced_monitoring = true

  # Lambda processor configuration
  lambda_source_path = "${path.module}/../../lambda/payments"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 512
  lambda_timeout     = 30

  # Event source mapping
  batch_size           = 25
  batch_window_seconds = 5
  starting_position    = "LATEST"

  # Error handling
  dlq_enabled            = true
  max_retry_attempts     = 3
  max_record_age_seconds = 3600

}


# =============================================================================
# Additional Consumer: analytics_aggregator
# Source streams: user_activity, payments
# =============================================================================

data "archive_file" "analytics_aggregator" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/analytics_aggregator"
  output_path = "${path.module}/.terraform/tmp/analytics_aggregator-lambda.zip"
}

resource "aws_cloudwatch_log_group" "analytics_aggregator" {
  name              = "/aws/lambda/dev-analytics_aggregator"
  retention_in_days = 14
}

resource "aws_iam_role" "analytics_aggregator" {
  name = "dev-analytics_aggregator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_aggregator_basic" {
  role       = aws_iam_role.analytics_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "analytics_aggregator_kinesis" {
  name = "dev-analytics_aggregator-kinesis-access"

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
        Resource = [module.user_activity_events.stream_arn, module.payments_events.stream_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.user_activity_events.kms_key_arn, module.payments_events.kms_key_arn]
      },
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [module.user_activity_events.dlq_arn, module.payments_events.dlq_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_aggregator_kinesis" {
  role       = aws_iam_role.analytics_aggregator.name
  policy_arn = aws_iam_policy.analytics_aggregator_kinesis.arn
}

resource "aws_lambda_function" "analytics_aggregator" {
  function_name = "dev-analytics_aggregator"
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

resource "aws_lambda_event_source_mapping" "analytics_aggregator_user_activity" {
  event_source_arn  = module.user_activity_events.stream_arn
  function_name     = aws_lambda_function.analytics_aggregator.arn
  starting_position = "LATEST"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 1

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  destination_config {
    on_failure {
      destination_arn = module.user_activity_events.dlq_arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.analytics_aggregator_kinesis]
}

resource "aws_lambda_event_source_mapping" "analytics_aggregator_payments" {
  event_source_arn  = module.payments_events.stream_arn
  function_name     = aws_lambda_function.analytics_aggregator.arn
  starting_position = "LATEST"

  batch_size                         = 100
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 1

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  destination_config {
    on_failure {
      destination_arn = module.payments_events.dlq_arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.analytics_aggregator_kinesis]
}


# =============================================================================
# Additional Consumer: fraud_detector
# Source streams: payments
# =============================================================================

data "archive_file" "fraud_detector" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/fraud_detector"
  output_path = "${path.module}/.terraform/tmp/fraud_detector-lambda.zip"
}

resource "aws_cloudwatch_log_group" "fraud_detector" {
  name              = "/aws/lambda/dev-fraud_detector"
  retention_in_days = 14
}

resource "aws_iam_role" "fraud_detector" {
  name = "dev-fraud_detector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fraud_detector_basic" {
  role       = aws_iam_role.fraud_detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "fraud_detector_kinesis" {
  name = "dev-fraud_detector-kinesis-access"

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
        Resource = [module.payments_events.stream_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [module.payments_events.kms_key_arn]
      },
      {
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [module.payments_events.dlq_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fraud_detector_kinesis" {
  role       = aws_iam_role.fraud_detector.name
  policy_arn = aws_iam_policy.fraud_detector_kinesis.arn
}

resource "aws_lambda_function" "fraud_detector" {
  function_name = "dev-fraud_detector"
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
  event_source_arn  = module.payments_events.stream_arn
  function_name     = aws_lambda_function.fraud_detector.arn
  starting_position = "LATEST"

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  parallelization_factor             = 1

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  destination_config {
    on_failure {
      destination_arn = module.payments_events.dlq_arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.fraud_detector_kinesis]
}


# =============================================================================
# API Gateway
# =============================================================================

module "api_gateway" {
  source = "../../../kinesis-infra/modules/api_gateway"

  name        = "events-ingestion"
  environment = var.environment
  description = "Unified API Gateway for event ingestion"

  event_streams = {
    user_activity = {
      stream_name = module.user_activity_events.stream_name
      stream_arn  = module.user_activity_events.stream_arn
      kms_key_arn = module.user_activity_events.kms_key_arn
    }
    orders = {
      stream_name = module.orders_events.stream_name
      stream_arn  = module.orders_events.stream_arn
      kms_key_arn = module.orders_events.kms_key_arn
    }
    payments = {
      stream_name = module.payments_events.stream_name
      stream_arn  = module.payments_events.stream_arn
      kms_key_arn = module.payments_events.kms_key_arn
    }
  }

  stage_name             = "v1"
  throttling_rate_limit  = 10000
  throttling_burst_limit = 5000
  enable_access_logging  = true
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
  value = {
    stream_name   = module.user_activity_events.stream_name
    stream_arn    = module.user_activity_events.stream_arn
    processor     = module.user_activity_events.lambda_function_name
    dlq_url       = module.user_activity_events.dlq_url
  }
}

output "orders_stream" {
  value = {
    stream_name   = module.orders_events.stream_name
    stream_arn    = module.orders_events.stream_arn
    processor     = module.orders_events.lambda_function_name
    dlq_url       = module.orders_events.dlq_url
  }
}

output "payments_stream" {
  value = {
    stream_name   = module.payments_events.stream_name
    stream_arn    = module.payments_events.stream_arn
    processor     = module.payments_events.lambda_function_name
    dlq_url       = module.payments_events.dlq_url
  }
}

output "analytics_aggregator_consumer" {
  value = {
    lambda_name = aws_lambda_function.analytics_aggregator.function_name
    lambda_arn  = aws_lambda_function.analytics_aggregator.arn
  }
}

output "fraud_detector_consumer" {
  value = {
    lambda_name = aws_lambda_function.fraud_detector.function_name
    lambda_arn  = aws_lambda_function.fraud_detector.arn
  }
}
