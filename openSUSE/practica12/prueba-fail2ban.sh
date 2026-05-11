#!/bin/bash

echo "[..] Enviando 6 intentos de login fallidos por IMAPS..."
for i in $(seq 1 6); do
    echo "    Intento $i..."
    curl -s --max-time 5 imaps://mail.reprobados.com \
         --user "dualy@reprobados.com:contraseniaMAL" \
         --insecure || true
    sleep 2
done

echo ""
echo "[..] Verificando bloqueo en Fail2ban..."
docker exec mailserver fail2ban-client status dovecot
