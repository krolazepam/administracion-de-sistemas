# ============================================================
# Dockerfile personalizado - PostgreSQL
# ============================================================
# Base: postgres:16-alpine (ligera)
# Incluye script de inicialización con tabla de usuarios
# ============================================================

FROM postgres:16-alpine

LABEL maintainer="practica-docker"
LABEL description="PostgreSQL endurecido sobre Alpine"

# Los scripts en /docker-entrypoint-initdb.d se ejecutan SOLO la primera vez
# que se inicializa el volumen db_data (es decir, cuando está vacío)
COPY init/ /docker-entrypoint-initdb.d/

# Healthcheck con pg_isready
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" || exit 1

EXPOSE 5432
