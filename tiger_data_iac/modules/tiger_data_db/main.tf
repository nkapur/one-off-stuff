locals {
  # Define your hardware "T-Shirt" mapping
  size_config = {
    small  = { cpu = 2000, mem = 8,  ha = false }
    medium = { cpu = 4000, mem = 16, ha = true }
    large  = { cpu = 8000, mem = 32, ha = true }
  }

  current_spec = local.size_config[var.size]

  # Deletion protection for prod and staging environments
  is_protected = contains(["prod", "staging"], var.deployment_mode)
}

# Protected resource (prod/staging) - prevent_destroy must be a literal
resource "timescale_service" "protected" {
  count             = local.is_protected ? 1 : 0
  name              = var.instance_name
  milli_cpu         = local.current_spec.cpu
  memory_gb         = local.current_spec.mem
  region_code       = var.region
  enable_ha_replica = local.current_spec.ha

  lifecycle {
    prevent_destroy = true
  }
}

# Unprotected resource (dev) - no deletion protection
resource "timescale_service" "unprotected" {
  count             = local.is_protected ? 0 : 1
  name              = var.instance_name
  milli_cpu         = local.current_spec.cpu
  memory_gb         = local.current_spec.mem
  region_code       = var.region
  enable_ha_replica = local.current_spec.ha
}

locals {
  # Reference the active service instance
  service = local.is_protected ? timescale_service.protected[0] : timescale_service.unprotected[0]
}

output "hostname" {
    value = local.service.hostname
}

output "connection_string" {
    value = "postgresql://${local.service.username}:${local.service.password}@${local.service.hostname}:${local.service.port}/tsdb?sslmode=require"
}