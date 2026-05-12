#!/bin/bash

PINK='\033[38;5;213m'
ROSE='\033[38;5;211m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

DIR="$(cd "$(dirname "$0")" && pwd)"

menu() {
    clear
    echo ""
    echo -e "  ${PINK}${BOLD}✦ Panel de Control${RESET}  ${DIM}· mail.reprobados.com${RESET}"
    echo ""
    echo -e "  ${ROSE}1${RESET}  Cuentas de correo"
    echo -e "  ${ROSE}2${RESET}  IPs baneadas"
    echo -e "  ${ROSE}3${RESET}  Probar bloqueo automático"
    echo -e "  ${ROSE}4${RESET}  Renovar certificados SSL"
    echo -e "  ${ROSE}5${RESET}  Estado de los contenedores"
    echo ""
    echo -e "  ${DIM}0  Salir${RESET}"
    echo ""
}

while true; do
    menu
    read -rp "$(echo -e "  ${PINK}❯${RESET} ")" OPCION
    echo ""

    case "$OPCION" in
        1) bash "$DIR/cuentas.sh" ;;
        2) bash "$DIR/ips-baneadas.sh" ;;
        3) bash "$DIR/probar-bloqueo.sh" ; echo "" ; read -rp "$(echo -e "  ${DIM}Pulsa Enter para volver...${RESET}")" ;;
        4) bash "$DIR/generar-certs.sh" ; echo "" ; read -rp "$(echo -e "  ${DIM}Pulsa Enter para volver...${RESET}")" ;;
        5)
            echo -e "  ${PINK}${BOLD}Contenedores activos${RESET}"
            echo ""
            docker compose -f "$DIR/docker-compose.yml" ps
            echo ""
            read -rp "$(echo -e "  ${DIM}Pulsa Enter para volver...${RESET}")"
            ;;
        0)
            echo -e "  ${PINK}Hasta luego ♡${RESET}"
            echo ""
            exit 0
            ;;
        *)
            echo -e "  ${DIM}Opción no válida${RESET}"
            sleep 1
            ;;
    esac
done
