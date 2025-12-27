# =============================================================================
# Kinesis Event Flow Module
# Creates a Kinesis stream with a zero-scaled Lambda subscriber
# =============================================================================

locals {
  resource_prefix = "${var.environment}-${var.event_type}"

  default_tags = {
    Environment = var.environment
    EventType   = var.event_type
    ManagedBy   = "terraform"
    Module      = "kinesis_event_flow"
  }

  all_tags = merge(local.default_tags, var.tags)
}

# -----------------------------------------------------------------------------
# Kinesis Data Stream
# -----------------------------------------------------------------------------

resource "aws_kinesis_stream" "events" {
  name             = "${local.resource_prefix}-stream"
  shard_count      = var.shard_count
  retention_period = var.retention_period

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = aws_kms_key.stream_encryption.arn

  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds"
  ] : []

  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# KMS Key for Stream Encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "stream_encryption" {
  description             = "KMS key for ${local.resource_prefix} Kinesis stream encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.all_tags
}

resource "aws_kms_alias" "stream_encryption" {
  name          = "alias/${local.resource_prefix}-kinesis"
  target_key_id = aws_kms_key.stream_encryption.key_id
}

# -----------------------------------------------------------------------------
# Dead Letter Queue (SQS) for Failed Records
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  count = var.dlq_enabled ? 1 : 0

  name                       = "${local.resource_prefix}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  sqs_managed_sse_enabled = true

  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# Lambda Function - Event Processor (Zero-scaled by default)
# -----------------------------------------------------------------------------

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = var.lambda_source_path
  output_path = "${path.module}/.terraform/tmp/${local.resource_prefix}-lambda.zip"
}

resource "aws_lambda_function" "processor" {
  function_name = "${local.resource_prefix}-processor"
  role          = aws_iam_role.lambda_execution.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Reserved concurrency = 0 means the function is disabled
  # Lambda automatically scales to 0 when not processing events
  # No reserved concurrency set = unlimited scaling based on demand

  environment {
    variables = merge(
      {
        EVENT_TYPE  = var.event_type
        ENVIRONMENT = var.environment
        STREAM_NAME = aws_kinesis_stream.events.name
        DLQ_URL     = var.dlq_enabled ? aws_sqs_queue.dlq[0].url : ""
      },
      var.lambda_environment_variables
    )
  }

  dynamic "vpc_config" {
    for_each = var.lambda_vpc_config != null ? [var.lambda_vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_kinesis_access,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Lambda
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-processor"
  retention_in_days = 14

  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# Lambda Event Source Mapping (Kinesis Trigger)
# This is what enables zero-scaling: Lambda only runs when events arrive
# -----------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.events.arn
  function_name     = aws_lambda_function.processor.arn
  starting_position = var.starting_position

  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.batch_window_seconds
  parallelization_factor             = var.parallelization_factor

  # Error handling configuration
  maximum_retry_attempts         = var.max_retry_attempts
  maximum_record_age_in_seconds  = var.max_record_age_seconds
  bisect_batch_on_function_error = true

  # Send failed records to DLQ
  dynamic "destination_config" {
    for_each = var.dlq_enabled ? [1] : []
    content {
      on_failure {
        destination_arn = aws_sqs_queue.dlq[0].arn
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_kinesis_access
  ]
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_execution" {
  name = "${local.resource_prefix}-lambda-role"

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

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Kinesis read access
resource "aws_iam_policy" "kinesis_access" {
  name        = "${local.resource_prefix}-kinesis-access"
  description = "Allow Lambda to read from Kinesis stream"

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
        Resource = aws_kinesis_stream.events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.stream_encryption.arn
      }
    ]
  })

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.kinesis_access.arn
}

# DLQ write access
resource "aws_iam_policy" "dlq_access" {
  count = var.dlq_enabled ? 1 : 0

  name        = "${local.resource_prefix}-dlq-access"
  description = "Allow Lambda to write to DLQ"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.dlq[0].arn
      }
    ]
  })

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "lambda_dlq_access" {
  count = var.dlq_enabled ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.dlq_access[0].arn
}

# VPC access (if configured)
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  count = var.lambda_vpc_config != null ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  alarm_name          = "${local.resource_prefix}-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Maximum"
  threshold           = 60000 # 1 minute
  alarm_description   = "Kinesis iterator age is too high - consumer is falling behind"

  dimensions = {
    StreamName = aws_kinesis_stream.events.name
  }

  tags = local.all_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda function error rate is elevated"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  tags = local.all_tags
}

