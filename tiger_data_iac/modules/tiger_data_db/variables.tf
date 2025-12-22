variable "instance_name" {
    type = string
    description = "The name of the instance"
}

variable "size" {
    type = string
    description = "The size of the instance. Options are: small (AI/Analytics focused), medium (Hybrid), large"
}

variable "region" {
    type = string
    default = "us-east-1"
}

variable "extensions" {
    type = list(string)
    description = "List of PostgreSQL extensions to enable (e.g., ['vector', 'postgis'])"
    default     = []
}

variable "deployment_mode" {
    type        = string
    description = "Options: prod, staging, dev. prod/staging have deletion protection, dev does not."

    validation {
        condition     = contains(["prod", "staging", "dev"], var.deployment_mode)
        error_message = "deployment_mode must be one of: prod, staging, dev"
    }
}