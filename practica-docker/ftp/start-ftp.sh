#!/bin/bash
# ============================================================
# start-ftp.sh - Arranque del servidor pure-ftpd
# ============================================================
# - Crea un usuario del sistema (ftpuser) si no existe
# - Crea un usuario VIRTUAL de pure-ftpd mapeado a ftpuser
# - Configura passivo para funcionar detrás de Docker NAT
# - Asegura permisos sobre el volumen compartido
# ============================================================

set -e

FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftppass123}"
PASV_ADDRESS="${PASV_ADDRESS:-127.0.0.1}"
FTP_HOME="/home/ftpuser"

echo "[FTP] Iniciando configuración..."
echo "[FTP] Usuario: $FTP_USER"
echo "[FTP] Dirección pasiva: $PASV_ADDRESS"

# 1) Crear usuario del sistema (si no existe) - necesario como UID real
if ! id -u ftpuser >/dev/null 2>&1; then
    echo "[FTP] Creando usuario del sistema 'ftpuser'..."
    adduser -D -H -h "$FTP_HOME" -s /sbin/nologin ftpuser
fi

# 2) Asegurar permisos sobre el home (volumen compartido con el web)
chown -R ftpuser:ftpuser "$FTP_HOME"
chmod -R 755 "$FTP_HOME"

# 3) Crear usuario VIRTUAL de pure-ftpd
#    -f: archivo, -u: uid real, -d: home restringido (chroot)
echo "[FTP] Registrando usuario virtual '$FTP_USER'..."
(echo "$FTP_PASS"; echo "$FTP_PASS") | \
    pure-pw useradd "$FTP_USER" \
        -u ftpuser \
        -g ftpuser \
        -d "$FTP_HOME" \
        -f /etc/pure-ftpd/passwd/pureftpd.passwd \
        -m 2>/dev/null || \
    (echo "$FTP_PASS"; echo "$FTP_PASS") | \
        pure-pw passwd "$FTP_USER" \
            -f /etc/pure-ftpd/passwd/pureftpd.passwd \
            -m

# 4) Compilar base de datos de usuarios
pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb \
    -f /etc/pure-ftpd/passwd/pureftpd.passwd

# 5) Iniciar pure-ftpd
#    -l puredb: usar base de datos de usuarios virtuales
#    -E: solo usuarios autenticados (sin anonymous)
#    -j: crear home si no existe
#    -R: prohibir comando CHMOD (seguridad)
#    -p 30000:30009: rango pasivo
#    -P: dirección pública para modo pasivo
#    -A: chroot a directorio home
echo "[FTP] Iniciando pure-ftpd..."
exec pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E \
    -j \
    -R \
    -A \
    -p 30000:30009 \
    -P "$PASV_ADDRESS" \
    -d
