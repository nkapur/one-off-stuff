variable "tiger_data_project_id" {
  type = string
  description = "The project ID for the Tiger Data project"
}

variable "tiger_data_pub_key" {
  type = string
  description = "The pub key for the Tiger Data project"
}

variable "tiger_data_secret_key" {
  type = string
  description = "The secret key for the Tiger Data project"
}

terraform {
  required_providers {
    timescale = {
      source  = "timescale/timescale"
      version = "~> 1.1.0" # Use the latest stable version
    }
  }
}

provider "timescale" {
  project_id = var.tiger_data_project_id
  access_key = var.tiger_data_pub_key
  secret_key = var.tiger_data_secret_key
}

resource "timescale_service" "analytics_db" {
  name      = "production-analytics"
  milli_cpu = 2000        # 2 CPUs
  memory_gb = 8           # 8 GB RAM
  region_code = "us-east-1"
  
  # Highly recommended for production to prevent accidental deletions
  lifecycle {
    prevent_destroy = false
  }
}