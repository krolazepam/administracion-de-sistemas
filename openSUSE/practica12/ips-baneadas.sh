#!/bin/bash

PINK='\033[38;5;213m'
ROSE='\033[38;5;211m'
HOT='\033[38;5;198m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "  ${HOT}✓${RESET} $*"; }
err()  { echo -e "  ${ROSE}✗${RESET} $*"; }
warn() { echo -e "  ${PINK}!${RESET} $*"; }

titulo() {
    clear
    echo ""
    echo -e "  ${PINK}${BOLD}✦ IPs baneadas${RESET}  ${DIM}· Fail2ban${RESET}"
    echo ""
}

obtener_jails() {
    docker exec mailserver fail2ban-client status 2>/dev/null \
        | grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | tr -d ' '
}

listar_baneadas() {
    JAILS=$(obtener_jails)
    if [[ -z "$JAILS" ]]; then
        warn "No se pudo contactar con Fail2ban"; return 1
    fi

    HAY_BANEADAS=0
    while IFS= read -r JAIL; do
        IPS=$(docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep "Banned IP list" | sed 's/.*Banned IP list:\s*//')
        if [[ -n "$IPS" && "$IPS" != " " ]]; then
            echo -e "  ${DIM}$JAIL${RESET}"
            for IP in $IPS; do
                echo -e "    ${ROSE}·${RESET} $IP"
                HAY_BANEADAS=1
            done
            echo ""
        fi
    done <<< "$JAILS"

    if [[ "$HAY_BANEADAS" -eq 0 ]]; then
        echo -e "  ${DIM}No hay IPs baneadas actualmente${RESET}"
        echo ""
    fi
}

desbanear_ip() {
    listar_baneadas || return

    read -rp "$(echo -e "  ${PINK}IP a desbanear:${RESET} ")" IP

    if [[ -z "$IP" ]]; then err "La IP no puede estar vacía"; return; fi
    if [[ ! "$IP" =~ ^[0-9a-fA-F.:]+$ ]]; then err "Formato de IP no válido"; return; fi

    echo ""
    JAILS=$(obtener_jails)
    DESBANEADA=0

    while IFS= read -r JAIL; do
        IPS=$(docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep "Banned IP list" | sed 's/.*Banned IP list:\s*//')
        if echo "$IPS" | grep -qw "$IP"; then
            if docker exec mailserver fail2ban-client set "$JAIL" unbanip "$IP" 2>/dev/null; then
                ok "$IP desbaneada del jail $JAIL"
                DESBANEADA=1
            else
                err "No se pudo desbanear $IP del jail $JAIL"
            fi
        fi
    done <<< "$JAILS"

    [[ "$DESBANEADA" -eq 0 ]] && warn "$IP no estaba baneada en ningún jail"
    echo ""
}

estado_jails() {
    JAILS=$(obtener_jails)
    if [[ -z "$JAILS" ]]; then
        warn "No se pudo contactar con Fail2ban"; return
    fi

    while IFS= read -r JAIL; do
        echo -e "  ${PINK}${BOLD}$JAIL${RESET}"
        docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep -E "Currently (failed|banned)|Total (failed|banned)|Banned IP" \
            | sed "s/^/    /"
        echo ""
    done <<< "$JAILS"
}

while true; do
    titulo

    echo -e "  ${ROSE}1${RESET}  Ver IPs baneadas"
    echo -e "  ${ROSE}2${RESET}  Desbanear una IP"
    echo -e "  ${ROSE}3${RESET}  Estado de los jails"
    echo ""
    echo -e "  ${DIM}0  Volver${RESET}"
    echo ""
    read -rp "$(echo -e "  ${PINK}❯${RESET} ")" OPCION
    echo ""

    case "$OPCION" in
        1) listar_baneadas ;;
        2) desbanear_ip ;;
        3) estado_jails ;;
        0) exit 0 ;;
        *) err "Opción no válida" ; sleep 1 ;;
    esac
done
