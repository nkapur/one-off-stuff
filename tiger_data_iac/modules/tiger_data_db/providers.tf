terraform {
    required_providers {
        timescale = {
            source = "timescale/timescale"
            version = "~> 1.1.0"
        }
        postgresql = {
            source = "cyrilgdn/postgresql"
            version = "~> 1.22.0"
        }
        external = {
            source = "hashicorp/external"
            version = "~> 2.3"
        }
    }
}

# Read Timescale credentials from environment variables
data "external" "timescale_creds" {
    program = ["sh", "-c", <<-EOF
        echo "{\"project_id\": \"$TIMESCALE_PROJECT_ID\", \"access_key\": \"$TIMESCALE_ACCESS_KEY\", \"secret_key\": \"$TIMESCALE_SECRET_KEY\"}"
    EOF
    ]
}

provider "timescale" {
    project_id = data.external.timescale_creds.result.project_id
    access_key = data.external.timescale_creds.result.access_key
    secret_key = data.external.timescale_creds.result.secret_key
}

# The PostgreSQL provider uses the active service instance
provider "postgresql" {
    host     = local.service.hostname
    port     = local.service.port
    database = "tsdb"
    username = local.service.username
    password = local.service.password
    sslmode  = "require"
    connect_timeout = 15
}