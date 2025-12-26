# =============================================================================
# API Gateway Module - Outputs
# =============================================================================

output "api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.events.id
}

output "api_arn" {
  description = "ARN of the REST API"
  value       = aws_api_gateway_rest_api.events.arn
}

output "api_name" {
  description = "Name of the REST API"
  value       = aws_api_gateway_rest_api.events.name
}

output "invoke_url" {
  description = "Base URL to invoke the API"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "stage_name" {
  description = "Name of the deployment stage"
  value       = aws_api_gateway_stage.main.stage_name
}

output "execution_arn" {
  description = "Execution ARN of the API"
  value       = aws_api_gateway_rest_api.events.execution_arn
}

output "event_endpoints" {
  description = "Map of event types to their POST endpoints"
  value = {
    for event_type, config in var.event_streams :
    event_type => {
      single = "${aws_api_gateway_stage.main.invoke_url}/events/${event_type}"
      batch  = "${aws_api_gateway_stage.main.invoke_url}/events/batch/${event_type}"
    }
  }
}

output "api_gateway_role_arn" {
  description = "ARN of the IAM role used by API Gateway"
  value       = aws_iam_role.api_gateway_kinesis.arn
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for access logs"
  value       = var.enable_access_logging ? aws_cloudwatch_log_group.access_logs[0].name : null
}

