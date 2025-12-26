# Kinesis Event Ingestion Infrastructure

A modular Terraform infrastructure for building scalable, zero-scaled event processing pipelines using AWS Kinesis Data Streams.

## Architecture Overview

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                    AWS Cloud                             │
┌──────────────┐                    │                                                         │
│              │   POST /events/    │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│   Clients    │──────────────────▶ │  │             │    │   Kinesis   │    │   Lambda    │ │
│              │   user_activity    │  │     API     │───▶│   Stream    │───▶│  Processor  │ │
└──────────────┘                    │  │   Gateway   │    │ (per event) │    │(zero-scaled)│ │
       │                            │  │             │    └─────────────┘    └─────────────┘ │
       │        POST /events/       │  │  (Unified   │                              │        │
       ├───────────────────────────▶│  │   Entry     │    ┌─────────────┐           ▼        │
       │        orders              │  │   Point)    │───▶│   Kinesis   │    ┌─────────────┐ │
       │                            │  │             │    │   Stream    │───▶│   Lambda    │ │
       │        POST /events/       │  │             │    └─────────────┘    │  Processor  │ │
       └───────────────────────────▶│  │             │                       └─────────────┘ │
                payments            │  │             │    ┌─────────────┐           │        │
                                    │  │             │───▶│   Kinesis   │           ▼        │
                                    │  └─────────────┘    │   Stream    │    ┌─────────────┐ │
                                    │                     └─────────────┘───▶│   Lambda    │ │
                                    │                                        │  Processor  │ │
                                    │                                        └─────────────┘ │
                                    └─────────────────────────────────────────────────────────┘
```

## Key Features

- **Zero-Scaled Subscribers**: Lambda functions automatically scale to zero when no events are available, minimizing costs
- **Modular Design**: Easily add new event types/families by instantiating new modules
- **Unified API Gateway**: Single entry point for all event types with automatic routing
- **Dead Letter Queue**: Failed records are sent to SQS for investigation and retry
- **Encryption at Rest**: All streams use KMS encryption
- **Enhanced Monitoring**: Optional shard-level CloudWatch metrics
- **Batch Processing**: Configurable batch sizes and windowing for efficient processing
- **CORS Support**: Pre-configured CORS headers for web client access

## Modules

### `kinesis_event_flow`

Creates a Kinesis stream with a zero-scaled Lambda subscriber.

#### Usage

```hcl
module "my_events" {
  source = "./modules/kinesis_event_flow"
  
  event_type  = "my_event_type"
  environment = "dev"
  
  # Stream configuration
  shard_count      = 1
  retention_period = 24
  
  # Lambda processor
  lambda_source_path = "${path.module}/lambda/my_handler"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = 256
  lambda_timeout     = 30
  
  # Batching
  batch_size           = 100
  batch_window_seconds = 5
  
  # Error handling
  dlq_enabled        = true
  max_retry_attempts = 3
}
```

#### Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `event_type` | Event type identifier | `string` | required |
| `environment` | Deployment environment | `string` | `"dev"` |
| `shard_count` | Number of shards | `number` | `1` |
| `retention_period` | Data retention in hours | `number` | `24` |
| `lambda_source_path` | Path to Lambda source | `string` | required |
| `lambda_handler` | Lambda handler | `string` | `"handler.process_event"` |
| `lambda_runtime` | Lambda runtime | `string` | `"python3.11"` |
| `lambda_memory_size` | Memory in MB | `number` | `256` |
| `lambda_timeout` | Timeout in seconds | `number` | `30` |
| `batch_size` | Max records per batch | `number` | `100` |
| `batch_window_seconds` | Batch window duration | `number` | `5` |
| `dlq_enabled` | Enable Dead Letter Queue | `bool` | `true` |
| `max_retry_attempts` | Max retry attempts | `number` | `3` |

### `api_gateway`

Creates a unified REST API Gateway that routes events to appropriate Kinesis streams.

#### Usage

```hcl
module "api_gateway" {
  source = "./modules/api_gateway"
  
  name        = "events-ingestion"
  environment = "dev"
  
  event_streams = {
    my_event_type = {
      stream_name = module.my_events.stream_name
      stream_arn  = module.my_events.stream_arn
      kms_key_arn = module.my_events.kms_key_arn
    }
  }
  
  stage_name             = "v1"
  throttling_rate_limit  = 10000
  enable_access_logging  = true
}
```

## Quick Start

### 1. Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Python 3.11+ (for Lambda development)

### 2. Initialize Terraform

```bash
cd kinesis-starter-infra
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Deploy

```bash
terraform apply
```

### 5. Test the Endpoints

```bash
# Get the API Gateway URL
API_URL=$(terraform output -raw api_gateway_url)

# Send a user activity event
curl -X POST "${API_URL}/events/user_activity" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user123",
    "action": "page_view",
    "timestamp": "2024-01-15T10:30:00Z",
    "metadata": {
      "page": "/products",
      "referrer": "google.com"
    }
  }'

# Send an order event
curl -X POST "${API_URL}/events/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "order_id": "ORD-12345",
    "customer_id": "CUST-001",
    "type": "created",
    "items": [{"sku": "PROD-001", "quantity": 2}],
    "total_amount": 99.99,
    "currency": "USD"
  }'

# Send batch events
curl -X POST "${API_URL}/events/batch/user_activity" \
  -H "Content-Type: application/json" \
  -d '{
    "records": [
      {"data": "{\"user_id\": \"user1\", \"action\": \"login\"}", "partitionKey": "user1"},
      {"data": "{\"user_id\": \"user2\", \"action\": \"signup\"}", "partitionKey": "user2"}
    ]
  }'
```

## Adding New Event Types

To add a new event type, follow these steps:

### 1. Create Lambda Handler

Create a new directory under `lambda/` with your handler:

```python
# lambda/my_new_event/handler.py
import base64
import json
import logging

logger = logging.getLogger()
logger.setLevel("INFO")

def process_event(event, context):
    for record in event.get("Records", []):
        payload = json.loads(
            base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
        )
        # Your processing logic here
        logger.info(f"Processed: {payload}")
    
    return {"statusCode": 200}
```

### 2. Add Module in `main.tf`

```hcl
module "my_new_events" {
  source = "./modules/kinesis_event_flow"
  
  event_type         = "my_new_event"
  environment        = var.environment
  lambda_source_path = "${path.module}/lambda/my_new_event"
  
  # Configure as needed
  shard_count = 1
}
```

### 3. Register with API Gateway

Add the new stream to the `event_streams` map in the API Gateway module:

```hcl
module "api_gateway" {
  # ... existing config ...
  
  event_streams = {
    # ... existing streams ...
    
    my_new_event = {
      stream_name = module.my_new_events.stream_name
      stream_arn  = module.my_new_events.stream_arn
      kms_key_arn = module.my_new_events.kms_key_arn
    }
  }
}
```

### 4. Deploy

```bash
terraform apply
```

## Cost Optimization

### Zero-Scaling Benefits

- **Lambda**: Only charged when processing events (scales to 0 automatically)
- **Kinesis**: Charged per shard-hour (start with 1 shard, scale as needed)
- **API Gateway**: Pay per request

### Recommended Settings by Volume

| Daily Events | Shards | Batch Size | Batch Window |
|--------------|--------|------------|--------------|
| < 10K | 1 | 100 | 5s |
| 10K - 100K | 1-2 | 100 | 3s |
| 100K - 1M | 2-4 | 200 | 1s |
| > 1M | 4+ | 500 | 0s |

## Monitoring & Alerting

The module creates CloudWatch alarms for:

- **Iterator Age**: Alert when consumer falls behind
- **Lambda Errors**: Alert on elevated error rates

Access logs are available in CloudWatch Logs at:
- `/aws/apigateway/{environment}-events-ingestion/access-logs`
- `/aws/lambda/{environment}-{event_type}-processor`

## Security Considerations

1. **Encryption**: All Kinesis streams use KMS encryption
2. **IAM**: Least-privilege IAM roles for each component
3. **API Keys**: Enable `api_key_required = true` for production
4. **VPC**: Configure `lambda_vpc_config` for VPC-isolated processing
5. **CORS**: Restrict `cors_allowed_origins` in production

## License

MIT

