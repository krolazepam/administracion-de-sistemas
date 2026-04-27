#!/bin/bash
# ============================================================
# backup.sh - Genera respaldo comprimido de PostgreSQL
# ============================================================

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/backups/${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "[$(date)] ===== Iniciando respaldo ====="
echo "[$(date)] Archivo destino: $BACKUP_FILE"

# pg_dump con compresión gzip
PGPASSWORD="$DB_PASSWORD" pg_dump \
    -h "$DB_HOST" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --no-owner \
    --no-acl \
    --clean \
    --if-exists \
    | gzip > "$BACKUP_FILE"

# Verificar que se generó y no está vacío
if [ -s "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "[$(date)] ✓ Respaldo generado ($SIZE): $BACKUP_FILE"
else
    echo "[$(date)] ✗ ERROR: respaldo vacío, eliminando..."
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Rotación: mantener solo los últimos 7 respaldos
echo "[$(date)] Limpiando respaldos antiguos (>7)..."
cd /backups
ls -1t "${DB_NAME}_"*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "[$(date)] ===== Respaldo completado ====="
