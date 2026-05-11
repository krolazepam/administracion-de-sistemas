#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[..] Generando certificados SSL..."
mkdir -p config/ssl
chmod 777 config/ssl

docker run --rm \
  -v "$(pwd)/config/ssl:/ssl:z" \
  alpine sh -c "
    apk add --no-cache openssl -q &&
    openssl req -new -x509 -days 365 -nodes \
      -subj '/CN=mail.reprobados.com' \
      -out /ssl/mail.reprobados.com-cert.pem \
      -keyout /ssl/mail.reprobados.com-key.pem 2>/dev/null &&
    cat /ssl/mail.reprobados.com-key.pem /ssl/mail.reprobados.com-cert.pem \
      > /ssl/mail.reprobados.com-full.pem &&
    echo '[OK] Certificados generados'
  "

echo "[..] Reiniciando mailserver..."
docker compose stop mailserver
docker compose up -d mailserver

echo "[..] Esperando que mailserver inicialice..."
sleep 20

echo "[..] Aplicando orden correcto del certificado en Postfix..."
docker exec mailserver sh -c "
    cat /tmp/docker-mailserver/ssl/mail.reprobados.com-key.pem \
        /tmp/docker-mailserver/ssl/mail.reprobados.com-cert.pem \
        > /etc/dms/tls/mail.reprobados.com-full.pem && postfix reload
"
echo "[OK] Listo"
