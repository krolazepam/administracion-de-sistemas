#!/bin/bash
# ============================================================
# entrypoint.sh - Arranque del servicio de backup
# ============================================================

set -e

echo "[BACKUP] Iniciando servicio de respaldo automático"
echo "[BACKUP] Base de datos: $DB_HOST / $DB_NAME"
echo "[BACKUP] Cron programado: $BACKUP_CRON"
echo "[BACKUP] Destino: /backups (mapeado al host)"

# Exportar variables para que las vea el cron
printenv | grep -E '^(DB_|BACKUP_|TZ)' > /etc/environment

# Registrar crontab
echo "$BACKUP_CRON . /etc/environment; /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" \
    > /etc/crontabs/root

# Esperar a que la base esté lista (hasta 60s)
echo "[BACKUP] Esperando a que PostgreSQL esté disponible..."
for i in $(seq 1 30); do
    if PGPASSWORD="$DB_PASSWORD" pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        echo "[BACKUP] PostgreSQL listo."
        break
    fi
    sleep 2
done

# Hacer un respaldo inicial para tener evidencia desde el arranque
echo "[BACKUP] Ejecutando respaldo inicial..."
/usr/local/bin/backup.sh || echo "[BACKUP] Respaldo inicial falló (continuo de todos modos)"

# Crear archivo de log y mostrarlo en stdout
touch /var/log/backup.log

# Iniciar cron en foreground
echo "[BACKUP] Iniciando cron daemon..."
crond -f -l 2 &
CRON_PID=$!

# Seguir el log para que aparezca en `docker logs`
tail -f /var/log/backup.log &
TAIL_PID=$!

wait $CRON_PID
