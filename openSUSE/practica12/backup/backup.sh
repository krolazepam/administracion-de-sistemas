#!/bin/sh
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/backups/mail_${TIMESTAMP}.tar.gz"
LOG="/backups/backup.log"

if tar -czf "$BACKUP_FILE" /var/mail 2>/dev/null; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: $(basename $BACKUP_FILE) ($SIZE)" >> "$LOG"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: falló la creación del backup" >> "$LOG"
    exit 1
fi

# Conservar solo los últimos 7 respaldos
find /backups -name "mail_*.tar.gz" | sort | head -n -7 | xargs -r rm -f
