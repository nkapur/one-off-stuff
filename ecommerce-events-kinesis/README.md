# E-commerce Events Kinesis

Example project using the Kinesis Event Infrastructure.

## Structure

```
ecommerce-events-kinesis/
├── config.yaml           # Infrastructure definition
├── lambda/               # Lambda handlers
│   ├── user_activity/
│   ├── orders/
│   ├── payments/
│   ├── analytics_aggregator/
│   └── fraud_detector/
└── __generated__/        # Generated Terraform (gitignore recommended)
    ├── dev/
    └── prod/
```

## Workflow

```bash
# Generate infrastructure
python ../kinesis-infra/generate.py config.yaml dev

# Deploy
cd __generated__/dev
terraform init
terraform apply
```

## Config Overview

This project defines:

- **3 streams**: user_activity, orders, payments
- **3 primary processors**: One per stream
- **2 additional consumers**:
  - `analytics_aggregator` - reads from user_activity + payments
  - `fraud_detector` - additional consumer on payments

