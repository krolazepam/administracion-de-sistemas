#!/bin/sh
SSL_DIR=/etc/nginx/ssl

if [ ! -f "$SSL_DIR/cert.pem" ]; then
    mkdir -p "$SSL_DIR"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/cert.pem" \
        -subj "/CN=mail.reprobados.com/O=Reprobados/C=MX" \
        -quiet
    echo "[nginx] Certificado self-signed generado para mail.reprobados.com"
fi

exec nginx -g 'daemon off;'
