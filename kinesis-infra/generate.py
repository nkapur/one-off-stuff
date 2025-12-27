#!/usr/bin/env python3
"""
Kinesis Infrastructure Generator

Reads a YAML config from a customer project and generates Terraform configuration
using the shared kinesis_event_flow and api_gateway modules.

Usage (from customer project directory):
    python ../kinesis-infra/generate.py config.yaml dev
    python ../kinesis-infra/generate.py config.yaml prod
    
Example:
    cd ecommerce-events-kinesis
    python ../kinesis-infra/generate.py config.yaml dev
"""

import argparse
import os
import sys
from pathlib import Path

import yaml


def compute_relative_path(from_path: Path, to_path: Path) -> str:
    """Compute relative path from one location to another."""
    # Resolve to absolute paths
    from_abs = from_path.resolve()
    to_abs = to_path.resolve()
    
    # Compute relative path
    try:
        rel = os.path.relpath(to_abs, from_abs)
        return rel
    except ValueError:
        # Different drives on Windows
        return str(to_abs)


def generate_header(config: dict, env: str, project_name: str) -> str:
    """Generate Terraform header with providers."""
    region = config.get('region', 'us-east-1')
    
    return f'''# =============================================================================
# Generated Kinesis Event Infrastructure - {env.upper()}
# Project: {project_name}
# DO NOT EDIT - Regenerate with: python <platform>/generate.py config.yaml {env}
# =============================================================================

terraform {{
  required_version = ">= 1.5.0"

  required_providers {{
    aws = {{
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }}
    archive = {{
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }}
  }}

  # Uncomment for remote state
  # backend "s3" {{
  #   bucket         = "your-tfstate-bucket"
  #   key            = "{project_name}/{env}/terraform.tfstate"
  #   region         = "{region}"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }}
}}

provider "aws" {{
  region = "{region}"

  default_tags {{
    tags = {{
      Project     = "{project_name}"
      ManagedBy   = "terraform"
      Environment = "{env}"
    }}
  }}
}}

variable "environment" {{
  default = "{env}"
}}

data "aws_caller_identity" "current" {{}}
data "aws_region" "current" {{}}
'''


def generate_stream_module(
    stream_name: str, 
    stream_cfg: dict, 
    consumer_cfg: dict, 
    env: str,
    platform_modules_relpath: str,
    project_root_relpath: str
) -> str:
    """Generate Terraform module block using kinesis_event_flow."""
    shards = stream_cfg.get('shards', 1)
    retention = stream_cfg.get('retention_hours', 24)
    enhanced = stream_cfg.get('enhanced_monitoring', False)
    
    source = consumer_cfg.get('source', f'lambda/{stream_name}')
    memory = consumer_cfg.get('memory', 256)
    timeout = consumer_cfg.get('timeout', 30)
    batch_size = consumer_cfg.get('batch_size', 100)
    batch_window = consumer_cfg.get('batch_window', 5)
    env_vars = consumer_cfg.get('env', {})
    
    # Build environment variables
    env_lines = []
    for k, v in env_vars.items():
        env_lines.append(f'    {k} = "{v}"')
    env_block = '\n'.join(env_lines) if env_lines else ''
    env_section = f'''
  lambda_environment_variables = {{
{env_block}
  }}''' if env_lines else ''
    
    return f'''
# =============================================================================
# Stream + Processor: {stream_name}
# =============================================================================

module "{stream_name}_events" {{
  source = "{platform_modules_relpath}/kinesis_event_flow"

  event_type  = "{stream_name}"
  environment = var.environment

  # Stream configuration
  shard_count              = {shards}
  retention_period         = {retention}
  enable_enhanced_monitoring = {str(enhanced).lower()}

  # Lambda processor configuration
  lambda_source_path = "${{path.module}}/{project_root_relpath}/{source}"
  lambda_handler     = "handler.process_event"
  lambda_runtime     = "python3.11"
  lambda_memory_size = {memory}
  lambda_timeout     = {timeout}

  # Event source mapping
  batch_size           = {batch_size}
  batch_window_seconds = {batch_window}
  starting_position    = "LATEST"

  # Error handling
  dlq_enabled            = true
  max_retry_attempts     = 3
  max_record_age_seconds = 3600
{env_section}
}}
'''


def generate_additional_consumer(
    name: str, 
    cfg: dict, 
    env: str, 
    streams: dict,
    project_root_relpath: str
) -> str:
    """Generate inline Terraform for additional/multi-stream consumers."""
    source = cfg.get('source', f'lambda/{name}')
    memory = cfg.get('memory', 256)
    timeout = cfg.get('timeout', 30)
    batch_size = cfg.get('batch_size', 100)
    batch_window = cfg.get('batch_window', 5)
    env_vars = cfg.get('env', {})
    
    # Handle single or multiple streams
    stream_list = cfg.get('streams', [cfg.get('stream')])
    
    # Build environment variables block
    env_lines = [
        f'      LOG_LEVEL   = "INFO"',
        f'      ENVIRONMENT = var.environment',
    ]
    for k, v in env_vars.items():
        env_lines.append(f'      {k} = "{v}"')
    env_block = '\n'.join(env_lines)
    
    # Build IAM policy for stream access - reference module outputs
    stream_arns = ', '.join([f'module.{s}_events.stream_arn' for s in stream_list])
    kms_arns = ', '.join([f'module.{s}_events.kms_key_arn' for s in stream_list])
    dlq_arns = ', '.join([f'module.{s}_events.dlq_arn' for s in stream_list])
    
    # Build event source mappings
    event_sources = ''
    for stream in stream_list:
        event_sources += f'''
resource "aws_lambda_event_source_mapping" "{name}_{stream}" {{
  event_source_arn  = module.{stream}_events.stream_arn
  function_name     = aws_lambda_function.{name}.arn
  starting_position = "LATEST"

  batch_size                         = {batch_size}
  maximum_batching_window_in_seconds = {batch_window}
  parallelization_factor             = 1

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  destination_config {{
    on_failure {{
      destination_arn = module.{stream}_events.dlq_arn
    }}
  }}

  depends_on = [aws_iam_role_policy_attachment.{name}_kinesis]
}}
'''
    
    return f'''
# =============================================================================
# Additional Consumer: {name}
# Source streams: {', '.join(stream_list)}
# =============================================================================

data "archive_file" "{name}" {{
  type        = "zip"
  source_dir  = "${{path.module}}/{project_root_relpath}/{source}"
  output_path = "${{path.module}}/.terraform/tmp/{name}-lambda.zip"
}}

resource "aws_cloudwatch_log_group" "{name}" {{
  name              = "/aws/lambda/{env}-{name}"
  retention_in_days = 14
}}

resource "aws_iam_role" "{name}" {{
  name = "{env}-{name}-role"

  assume_role_policy = jsonencode({{
    Version = "2012-10-17"
    Statement = [{{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {{ Service = "lambda.amazonaws.com" }}
    }}]
  }})
}}

resource "aws_iam_role_policy_attachment" "{name}_basic" {{
  role       = aws_iam_role.{name}.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}}

resource "aws_iam_policy" "{name}_kinesis" {{
  name = "{env}-{name}-kinesis-access"

  policy = jsonencode({{
    Version = "2012-10-17"
    Statement = [
      {{
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards"
        ]
        Resource = [{stream_arns}]
      }},
      {{
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [{kms_arns}]
      }},
      {{
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [{dlq_arns}]
      }}
    ]
  }})
}}

resource "aws_iam_role_policy_attachment" "{name}_kinesis" {{
  role       = aws_iam_role.{name}.name
  policy_arn = aws_iam_policy.{name}_kinesis.arn
}}

resource "aws_lambda_function" "{name}" {{
  function_name = "{env}-{name}"
  role          = aws_iam_role.{name}.arn
  handler       = "handler.process_event"
  runtime       = "python3.11"

  filename         = data.archive_file.{name}.output_path
  source_code_hash = data.archive_file.{name}.output_base64sha256

  memory_size = {memory}
  timeout     = {timeout}

  environment {{
    variables = {{
{env_block}
    }}
  }}

  depends_on = [
    aws_iam_role_policy_attachment.{name}_basic,
    aws_iam_role_policy_attachment.{name}_kinesis,
    aws_cloudwatch_log_group.{name}
  ]
}}
{event_sources}'''


def generate_api_gateway(
    config: dict, 
    streams: dict, 
    env: str,
    platform_modules_relpath: str
) -> str:
    """Generate API Gateway configuration using module outputs."""
    gw = config.get('api_gateway', {})
    name = gw.get('name', 'events-ingestion')
    stage = gw.get('stage', 'v1')
    rate_limit = gw.get('throttling_rate_limit', 10000)
    burst_limit = gw.get('throttling_burst_limit', 5000)
    
    # Generate stream registrations using module outputs
    stream_configs = []
    for stream_name in streams.keys():
        stream_configs.append(f'''    {stream_name} = {{
      stream_name = module.{stream_name}_events.stream_name
      stream_arn  = module.{stream_name}_events.stream_arn
      kms_key_arn = module.{stream_name}_events.kms_key_arn
    }}''')
    
    streams_block = '\n'.join(stream_configs)
    
    return f'''
# =============================================================================
# API Gateway
# =============================================================================

module "api_gateway" {{
  source = "{platform_modules_relpath}/api_gateway"

  name        = "{name}"
  environment = var.environment
  description = "Unified API Gateway for event ingestion"

  event_streams = {{
{streams_block}
  }}

  stage_name             = "{stage}"
  throttling_rate_limit  = {rate_limit}
  throttling_burst_limit = {burst_limit}
  enable_access_logging  = true
}}
'''


def generate_outputs(streams: dict, additional_consumers: list) -> str:
    """Generate Terraform outputs."""
    output = '''
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
'''
    
    for name in streams.keys():
        output += f'''
output "{name}_stream" {{
  value = {{
    stream_name   = module.{name}_events.stream_name
    stream_arn    = module.{name}_events.stream_arn
    processor     = module.{name}_events.lambda_function_name
    dlq_url       = module.{name}_events.dlq_url
  }}
}}
'''
    
    for name in additional_consumers:
        output += f'''
output "{name}_consumer" {{
  value = {{
    lambda_name = aws_lambda_function.{name}.function_name
    lambda_arn  = aws_lambda_function.{name}.arn
  }}
}}
'''
    
    return output


def identify_primary_consumers(streams: dict, consumers: dict) -> tuple[dict, dict]:
    """
    Identify which consumers are 'primary' (1:1 with a stream) vs 'additional'.
    
    Primary consumers:
    - Named {stream_name}_processor
    - Only consume from one stream matching their name
    
    Additional consumers:
    - Multi-stream consumers
    - Extra consumers on streams that already have a primary
    """
    primary = {}  # stream_name -> consumer_config
    additional = {}  # consumer_name -> consumer_config
    
    for consumer_name, consumer_cfg in consumers.items():
        stream_list = consumer_cfg.get('streams', [consumer_cfg.get('stream')])
        
        # Multi-stream consumers are always additional
        if len(stream_list) > 1:
            additional[consumer_name] = consumer_cfg
            continue
        
        stream = stream_list[0]
        expected_primary_name = f"{stream}_processor"
        
        # Check if this is the primary processor for a stream
        if consumer_name == expected_primary_name and stream in streams:
            if stream not in primary:
                primary[stream] = consumer_cfg
            else:
                additional[consumer_name] = consumer_cfg
        else:
            additional[consumer_name] = consumer_cfg
    
    return primary, additional


def generate(
    config_path: Path, 
    env: str, 
    platform_path: Path,
    project_path: Path
) -> str:
    """Generate complete Terraform configuration from YAML."""
    with open(config_path) as f:
        config = yaml.safe_load(f)
    
    streams = config.get('streams', {})
    consumers = config.get('consumers', {})
    project_name = config.get('project_name', project_path.name)
    
    # Compute relative paths from __generated__/{env}/ to:
    # 1. Platform modules directory
    # 2. Project root (for lambda source)
    generated_dir = project_path / '__generated__' / env
    platform_modules = platform_path / 'modules'
    
    platform_modules_relpath = compute_relative_path(generated_dir, platform_modules)
    project_root_relpath = compute_relative_path(generated_dir, project_path)
    
    # Identify primary vs additional consumers
    primary_consumers, additional_consumers = identify_primary_consumers(streams, consumers)
    
    parts = [generate_header(config, env, project_name)]
    
    # Generate stream modules (with primary consumers)
    for stream_name, stream_cfg in streams.items():
        consumer_cfg = primary_consumers.get(stream_name, {
            'source': f'lambda/{stream_name}',
            'memory': 256,
            'timeout': 30,
            'batch_size': 100
        })
        parts.append(generate_stream_module(
            stream_name, stream_cfg, consumer_cfg, env,
            platform_modules_relpath, project_root_relpath
        ))
    
    # Generate additional consumers
    for consumer_name, consumer_cfg in additional_consumers.items():
        parts.append(generate_additional_consumer(
            consumer_name, consumer_cfg, env, streams,
            project_root_relpath
        ))
    
    # Generate API Gateway
    parts.append(generate_api_gateway(config, streams, env, platform_modules_relpath))
    
    # Generate outputs
    parts.append(generate_outputs(streams, list(additional_consumers.keys())))
    
    return '\n'.join(parts)


def main():
    # Determine platform path from script location
    script_path = Path(__file__).resolve()
    platform_path = script_path.parent  # kinesis-infra directory
    
    parser = argparse.ArgumentParser(
        description='Generate Terraform from YAML config (Platform Generator)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f'''
Platform location: {platform_path}

Examples (run from your project directory):
  python {script_path} config.yaml dev
  python {script_path} config.yaml prod
  python {script_path} config.yaml staging --dry-run
        '''
    )
    parser.add_argument('config', help='Path to config.yaml')
    parser.add_argument('env', choices=['dev', 'staging', 'prod'], 
                        help='Target environment')
    parser.add_argument('--dry-run', action='store_true',
                        help='Print to stdout instead of writing file')
    parser.add_argument('--project-dir', type=Path, default=Path.cwd(),
                        help='Project directory (default: current directory)')
    args = parser.parse_args()
    
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = args.project_dir / config_path
    
    if not config_path.exists():
        print(f"Error: Config file '{config_path}' not found", file=sys.stderr)
        sys.exit(1)
    
    try:
        tf = generate(config_path, args.env, platform_path, args.project_dir)
        
        if args.dry_run:
            print(tf)
        else:
            # Create __generated__/env directory and write main.tf
            generated_dir = args.project_dir / '__generated__' / args.env
            generated_dir.mkdir(parents=True, exist_ok=True)
            
            output_path = generated_dir / 'main.tf'
            with open(output_path, 'w') as f:
                f.write(tf)
            
            print(f"Generated {output_path}", file=sys.stderr)
            print(f"\nNext steps:", file=sys.stderr)
            print(f"  cd {generated_dir}", file=sys.stderr)
            print(f"  terraform init", file=sys.stderr)
            print(f"  terraform plan", file=sys.stderr)
            print(f"  terraform apply", file=sys.stderr)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
