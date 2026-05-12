#!/bin/bash

PINK='\033[38;5;213m'
ROSE='\033[38;5;211m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "  ${PINK}${BOLD}✦ Probar bloqueo automático${RESET}  ${DIM}· Fail2ban${RESET}"
echo ""
echo -e "  ${DIM}Enviando 6 intentos de login fallidos por IMAPS...${RESET}"
echo ""

for i in $(seq 1 6); do
    echo -e "  ${ROSE}·${RESET} Intento $i..."
    curl -s --max-time 5 imaps://mail.reprobados.com \
         --user "dualy@reprobados.com:contraseniaMAL" \
         --insecure || true
    sleep 2
done

echo ""
echo -e "  ${PINK}${BOLD}Verificando bloqueo en Fail2ban...${RESET}"
echo ""
docker exec mailserver fail2ban-client status dovecot
echo ""
