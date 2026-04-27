# ============================================================
# Dockerfile - Servicio de backup automatizado (sidecar)
# ============================================================
# - Imagen Alpine con postgresql-client y cron
# - Ejecuta pg_dump según BACKUP_CRON hacia /backups
# - /backups se monta al host ( ./backups ) vía bind mount
# ============================================================

FROM alpine:3.19

LABEL maintainer="practica-docker"
LABEL description="Backup automatizado de PostgreSQL"

RUN apk add --no-cache \
        postgresql16-client \
        bash \
        tzdata \
        dcron

# Copiar scripts
COPY backup.sh    /usr/local/bin/backup.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

# Crear directorio de backups
RUN mkdir -p /backups /var/log

# Zona horaria
ENV TZ=America/Mazatlan

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
