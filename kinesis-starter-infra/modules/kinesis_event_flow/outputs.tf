# =============================================================================
# Kinesis Event Flow Module - Outputs
# =============================================================================

output "stream_name" {
  description = "Name of the Kinesis stream"
  value       = aws_kinesis_stream.events.name
}

output "stream_arn" {
  description = "ARN of the Kinesis stream"
  value       = aws_kinesis_stream.events.arn
}

output "stream_shard_count" {
  description = "Number of shards in the stream"
  value       = aws_kinesis_stream.events.shard_count
}

output "lambda_function_name" {
  description = "Name of the Lambda processor function"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda processor function"
  value       = aws_lambda_function.processor.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue (if enabled)"
  value       = var.dlq_enabled ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue (if enabled)"
  value       = var.dlq_enabled ? aws_sqs_queue.dlq[0].arn : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for stream encryption"
  value       = aws_kms_key.stream_encryption.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for stream encryption"
  value       = aws_kms_key.stream_encryption.key_id
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "event_type" {
  description = "Event type identifier"
  value       = var.event_type
}

# Output for API Gateway integration
output "kinesis_put_record_role_policy" {
  description = "IAM policy document for API Gateway to put records to this stream"
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.stream_encryption.arn
      }
    ]
  })
}

