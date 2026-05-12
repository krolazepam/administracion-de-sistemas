#!/bin/bash

listar_baneadas() {
    echo ""
    echo "  IPs baneadas por jail:"
    echo ""

    JAILS=$(docker exec mailserver fail2ban-client status 2>/dev/null \
        | grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | tr -d ' ')

    if [[ -z "$JAILS" ]]; then
        echo "    (no se pudo obtener la lista de jails o Fail2ban no está activo)"
        echo ""
        return 1
    fi

    HAY_BANEADAS=0
    while IFS= read -r JAIL; do
        IPS=$(docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep "Banned IP list" | sed 's/.*Banned IP list:\s*//')
        if [[ -n "$IPS" && "$IPS" != " " ]]; then
            echo "    [$JAIL]"
            for IP in $IPS; do
                echo "      - $IP"
                HAY_BANEADAS=1
            done
            echo ""
        fi
    done <<< "$JAILS"

    if [[ "$HAY_BANEADAS" -eq 0 ]]; then
        echo "    (no hay IPs baneadas actualmente)"
        echo ""
    fi
}

desbanear_ip() {
    listar_baneadas || return

    read -rp "  IP a desbanear: " IP

    if [[ -z "$IP" ]]; then
        echo "  [ERROR] La IP no puede estar vacía"
        return
    fi

    # Validar formato IPv4 o IPv6 básico
    if [[ ! "$IP" =~ ^[0-9a-fA-F.:]+$ ]]; then
        echo "  [ERROR] Formato de IP no válido"
        return
    fi

    echo ""
    echo "  Buscando $IP en todos los jails..."

    JAILS=$(docker exec mailserver fail2ban-client status 2>/dev/null \
        | grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | tr -d ' ')

    DESBANEADA=0
    while IFS= read -r JAIL; do
        IPS=$(docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep "Banned IP list" | sed 's/.*Banned IP list:\s*//')
        if echo "$IPS" | grep -qw "$IP"; then
            if docker exec mailserver fail2ban-client set "$JAIL" unbanip "$IP" 2>/dev/null; then
                echo "  [OK] $IP desbaneada del jail: $JAIL"
                DESBANEADA=1
            else
                echo "  [ERROR] No se pudo desbanear $IP del jail: $JAIL"
            fi
        fi
    done <<< "$JAILS"

    if [[ "$DESBANEADA" -eq 0 ]]; then
        echo "  [WARN] $IP no estaba baneada en ningún jail"
    fi
    echo ""
}

estado_jails() {
    echo ""
    JAILS=$(docker exec mailserver fail2ban-client status 2>/dev/null \
        | grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | tr -d ' ')

    if [[ -z "$JAILS" ]]; then
        echo "  (no se pudo obtener información de Fail2ban)"
        echo ""
        return
    fi

    while IFS= read -r JAIL; do
        echo "  --- $JAIL ---"
        docker exec mailserver fail2ban-client status "$JAIL" 2>/dev/null \
            | grep -E "Currently (failed|banned)|Total (failed|banned)|Banned IP" \
            | sed 's/^/    /'
        echo ""
    done <<< "$JAILS"
}

# Menú principal
while true; do
    echo ""
    echo "======================================================"
    echo "  Gestión de IPs baneadas — Fail2ban"
    echo "======================================================"
    echo "  1) Ver IPs baneadas"
    echo "  2) Desbanear una IP"
    echo "  3) Estado completo de los jails"
    echo "  4) Salir"
    echo "======================================================"
    read -rp "  Opción: " OPCION
    echo ""

    case "$OPCION" in
        1) listar_baneadas ;;
        2) desbanear_ip ;;
        3) estado_jails ;;
        4) echo "  Hasta luego."; exit 0 ;;
        *) echo "  [ERROR] Opción inválida" ;;
    esac
done
