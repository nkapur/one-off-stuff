# =============================================================================
# API Gateway Module
# Creates a shared REST API Gateway that fronts all Kinesis event streams
# =============================================================================

locals {
  resource_prefix = "${var.environment}-${var.name}"

  default_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Module      = "api_gateway"
  }

  all_tags = merge(local.default_tags, var.tags)
}

# -----------------------------------------------------------------------------
# REST API Gateway
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "events" {
  name        = local.resource_prefix
  description = var.description

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.all_tags
}

# -----------------------------------------------------------------------------
# IAM Role for API Gateway to access Kinesis
# -----------------------------------------------------------------------------

resource "aws_iam_role" "api_gateway_kinesis" {
  name = "${local.resource_prefix}-apigw-kinesis-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = local.all_tags
}

resource "aws_iam_policy" "kinesis_put" {
  name        = "${local.resource_prefix}-kinesis-put"
  description = "Allow API Gateway to put records to Kinesis streams"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        for event_type, config in var.event_streams : {
          Effect = "Allow"
          Action = [
            "kinesis:PutRecord",
            "kinesis:PutRecords"
          ]
          Resource = config.stream_arn
        }
      ],
      [
        for event_type, config in var.event_streams : {
          Effect = "Allow"
          Action = [
            "kms:Encrypt",
            "kms:GenerateDataKey"
          ]
          Resource = config.kms_key_arn
        }
      ]
    )
  })

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "api_gateway_kinesis" {
  role       = aws_iam_role.api_gateway_kinesis.name
  policy_arn = aws_iam_policy.kinesis_put.arn
}

# -----------------------------------------------------------------------------
# /events Resource (parent for all event types)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_rest_api.events.root_resource_id
  path_part   = "events"
}

# -----------------------------------------------------------------------------
# Dynamic Resources for Each Event Type
# Creates: /events/{event_type} endpoints
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "event_type" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_resource.events.id
  path_part   = each.key
}

# POST method for each event type
resource "aws_api_gateway_method" "post_event" {
  for_each = var.event_streams

  rest_api_id      = aws_api_gateway_rest_api.events.id
  resource_id      = aws_api_gateway_resource.event_type[each.key].id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = var.api_key_required

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

# Kinesis integration for each event type
resource "aws_api_gateway_integration" "kinesis_put" {
  for_each = var.event_streams

  rest_api_id             = aws_api_gateway_rest_api.events.id
  resource_id             = aws_api_gateway_resource.event_type[each.key].id
  http_method             = aws_api_gateway_method.post_event[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:kinesis:action/PutRecord"
  credentials             = aws_iam_role.api_gateway_kinesis.arn

  request_templates = {
    "application/json" = <<EOF
{
  "StreamName": "${each.value.stream_name}",
  "Data": "$util.base64Encode($input.body)",
  "PartitionKey": "$context.requestId"
}
EOF
  }

  passthrough_behavior = "WHEN_NO_TEMPLATES"
}

# Response configuration
resource "aws_api_gateway_method_response" "success" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.post_event[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "success" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.post_event[each.key].http_method
  status_code = aws_api_gateway_method_response.success[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'${join(",", var.cors_allowed_origins)}'"
  }

  response_templates = {
    "application/json" = <<EOF
{
  "status": "accepted",
  "eventType": "${each.key}",
  "sequenceNumber": "$input.json('$.SequenceNumber')",
  "shardId": "$input.json('$.ShardId')"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.kinesis_put]
}

# Error response
resource "aws_api_gateway_method_response" "error" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.post_event[each.key].http_method
  status_code = "500"

  response_models = {
    "application/json" = "Error"
  }
}

resource "aws_api_gateway_integration_response" "error" {
  for_each = var.event_streams

  rest_api_id       = aws_api_gateway_rest_api.events.id
  resource_id       = aws_api_gateway_resource.event_type[each.key].id
  http_method       = aws_api_gateway_method.post_event[each.key].http_method
  status_code       = aws_api_gateway_method_response.error[each.key].status_code
  selection_pattern = "5\\d{2}"

  response_templates = {
    "application/json" = <<EOF
{
  "error": "Failed to ingest event",
  "eventType": "${each.key}"
}
EOF
  }

  depends_on = [aws_api_gateway_integration.kinesis_put]
}

# -----------------------------------------------------------------------------
# CORS Configuration (OPTIONS method for each event type)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_method" "options" {
  for_each = var.event_streams

  rest_api_id   = aws_api_gateway_rest_api.events.id
  resource_id   = aws_api_gateway_resource.event_type[each.key].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.event_type[each.key].id
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_allowed_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_allowed_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_allowed_origins)}'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# -----------------------------------------------------------------------------
# Batch Endpoint: /events/batch (accepts multiple events)
# -----------------------------------------------------------------------------

resource "aws_api_gateway_resource" "batch" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_resource.events.id
  path_part   = "batch"
}

resource "aws_api_gateway_resource" "batch_event_type" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  parent_id   = aws_api_gateway_resource.batch.id
  path_part   = each.key
}

resource "aws_api_gateway_method" "batch_post" {
  for_each = var.event_streams

  rest_api_id      = aws_api_gateway_rest_api.events.id
  resource_id      = aws_api_gateway_resource.batch_event_type[each.key].id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = var.api_key_required
}

resource "aws_api_gateway_integration" "kinesis_put_records" {
  for_each = var.event_streams

  rest_api_id             = aws_api_gateway_rest_api.events.id
  resource_id             = aws_api_gateway_resource.batch_event_type[each.key].id
  http_method             = aws_api_gateway_method.batch_post[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:kinesis:action/PutRecords"
  credentials             = aws_iam_role.api_gateway_kinesis.arn

  request_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
{
  "StreamName": "${each.value.stream_name}",
  "Records": [
    #foreach($record in $inputRoot.records)
    {
      "Data": "$util.base64Encode($record.data)",
      "PartitionKey": "$record.partitionKey"
    }#if($foreach.hasNext),#end
    #end
  ]
}
EOF
  }

  passthrough_behavior = "WHEN_NO_TEMPLATES"
}

resource "aws_api_gateway_method_response" "batch_success" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.batch_event_type[each.key].id
  http_method = aws_api_gateway_method.batch_post[each.key].http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "batch_success" {
  for_each = var.event_streams

  rest_api_id = aws_api_gateway_rest_api.events.id
  resource_id = aws_api_gateway_resource.batch_event_type[each.key].id
  http_method = aws_api_gateway_method.batch_post[each.key].http_method
  status_code = aws_api_gateway_method_response.batch_success[each.key].status_code

  response_templates = {
    "application/json" = <<EOF
{
  "status": "accepted",
  "eventType": "${each.key}",
  "failedRecordCount": $input.json('$.FailedRecordCount'),
  "records": $input.json('$.Records')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.kinesis_put_records]
}

# -----------------------------------------------------------------------------
# API Gateway Deployment & Stage
# -----------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.events.id

  triggers = {
    redeployment = sha256(jsonencode([
      aws_api_gateway_resource.events.id,
      aws_api_gateway_resource.event_type,
      aws_api_gateway_method.post_event,
      aws_api_gateway_integration.kinesis_put,
      aws_api_gateway_resource.batch_event_type,
      aws_api_gateway_method.batch_post,
      aws_api_gateway_integration.kinesis_put_records,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.kinesis_put,
    aws_api_gateway_integration_response.success,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration_response.options,
    aws_api_gateway_integration.kinesis_put_records,
    aws_api_gateway_integration_response.batch_success,
  ]
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.events.id
  stage_name    = var.stage_name

  xray_tracing_enabled = var.enable_xray_tracing

  dynamic "access_log_settings" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.access_logs[0].arn
      format = jsonencode({
        requestId          = "$context.requestId"
        ip                 = "$context.identity.sourceIp"
        caller             = "$context.identity.caller"
        user               = "$context.identity.user"
        requestTime        = "$context.requestTime"
        httpMethod         = "$context.httpMethod"
        resourcePath       = "$context.resourcePath"
        status             = "$context.status"
        protocol           = "$context.protocol"
        responseLength     = "$context.responseLength"
        integrationStatus  = "$context.integrationStatus"
        integrationLatency = "$context.integrationLatency"
      })
    }
  }

  tags = local.all_tags
}

# Method settings for throttling
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.events.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
    metrics_enabled        = true
    logging_level          = "INFO"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "access_logs" {
  count = var.enable_access_logging ? 1 : 0

  name              = "/aws/apigateway/${local.resource_prefix}/access-logs"
  retention_in_days = 14

  tags = local.all_tags
}

# Allow API Gateway to write to CloudWatch
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${local.resource_prefix}-apigw-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = local.all_tags
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

