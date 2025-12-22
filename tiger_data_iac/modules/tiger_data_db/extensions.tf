# Enable PostgreSQL extensions

resource "postgresql_extension" "timescaledb" {
  name = "timescaledb"
  depends_on = [timescale_service.protected, timescale_service.unprotected]
}

resource "postgresql_extension" "timescaledb_toolkit" {
    name = "timescaledb_toolkit"
    depends_on = [postgresql_extension.timescaledb]
}

resource "postgresql_extension" "pgvector" {
    name = "vector"
    depends_on = [timescale_service.protected, timescale_service.unprotected]
}

resource "postgresql_extension" "pgvectorscale" {
    name = "vectorscale"
    depends_on = [postgresql_extension.pgvector]
}

# Enable additional extensions if specified
resource "postgresql_extension" "extra_extensions" {
    for_each = toset(var.extensions)
    name = each.value
    depends_on = [
        postgresql_extension.pgvector, 
        postgresql_extension.pgvectorscale,
    ]
}