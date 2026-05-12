#!/bin/bash

PINK='\033[38;5;213m'
ROSE='\033[38;5;211m'
HOT='\033[38;5;198m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

DOMINIO="reprobados.com"

ok()   { echo -e "  ${HOT}✓${RESET} $*"; }
err()  { echo -e "  ${ROSE}✗${RESET} $*"; }
warn() { echo -e "  ${PINK}!${RESET} $*"; }

titulo() {
    clear
    echo ""
    echo -e "  ${PINK}${BOLD}✦ Cuentas de correo${RESET}  ${DIM}· $DOMINIO${RESET}"
    echo ""
}

listar_cuentas() {
    echo -e "  ${DIM}Cuentas existentes:${RESET}"
    echo ""
    docker exec mailserver setup email list 2>/dev/null | \
        sed "s/^/    /" || echo "    (no se pudo obtener la lista)"
    echo ""
}

agregar_cuenta() {
    titulo
    listar_cuentas

    while true; do
        read -rp "$(echo -e "  ${PINK}Usuario${RESET} (sin @$DOMINIO): ")" USUARIO
        [[ -z "$USUARIO" ]] && err "El usuario no puede estar vacío" && continue
        [[ ! "$USUARIO" =~ ^[a-zA-Z0-9._-]+$ ]] && \
            err "Solo letras, números, puntos, guiones y guiones bajos" && continue
        break
    done

    EMAIL="${USUARIO}@${DOMINIO}"

    if docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        warn "La cuenta $EMAIL ya existe"
        return
    fi

    echo ""
    while true; do
        read -rsp "$(echo -e "  ${PINK}Contraseña:${RESET}  ")" PASS; echo
        [[ -z "$PASS" ]] && err "La contraseña no puede estar vacía" && continue
        read -rsp "$(echo -e "  ${PINK}Confirmar:${RESET}   ")" PASS2; echo
        [[ "$PASS" != "$PASS2" ]] && err "Las contraseñas no coinciden" && continue
        break
    done

    echo ""
    if docker exec mailserver setup email add "$EMAIL" "$PASS" 2>/dev/null; then
        ok "Cuenta $EMAIL creada"
    else
        err "No se pudo crear la cuenta"
    fi
}

eliminar_cuenta() {
    titulo
    listar_cuentas

    read -rp "$(echo -e "  ${PINK}Usuario a eliminar${RESET} (sin @$DOMINIO): ")" USUARIO
    EMAIL="${USUARIO}@${DOMINIO}"

    if ! docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        err "La cuenta $EMAIL no existe"; return
    fi

    echo ""
    read -rp "$(echo -e "  ${ROSE}¿Confirmas eliminar $EMAIL? (s/N):${RESET} ")" CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo -e "  ${DIM}Cancelado${RESET}"; return
    fi

    echo ""
    if docker exec mailserver setup email del "$EMAIL" 2>/dev/null; then
        ok "Cuenta $EMAIL eliminada"
    else
        err "No se pudo eliminar la cuenta"
    fi
}

cambiar_contrasena() {
    titulo
    listar_cuentas

    read -rp "$(echo -e "  ${PINK}Usuario${RESET} (sin @$DOMINIO): ")" USUARIO
    EMAIL="${USUARIO}@${DOMINIO}"

    if ! docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        err "La cuenta $EMAIL no existe"; return
    fi

    echo ""
    while true; do
        read -rsp "$(echo -e "  ${PINK}Nueva contraseña:${RESET} ")" PASS; echo
        [[ -z "$PASS" ]] && err "La contraseña no puede estar vacía" && continue
        read -rsp "$(echo -e "  ${PINK}Confirmar:${RESET}        ")" PASS2; echo
        [[ "$PASS" != "$PASS2" ]] && err "Las contraseñas no coinciden" && continue
        break
    done

    echo ""
    if docker exec mailserver setup email update "$EMAIL" "$PASS" 2>/dev/null; then
        ok "Contraseña de $EMAIL actualizada"
    else
        err "No se pudo actualizar la contraseña"
    fi
}

while true; do
    titulo

    echo -e "  ${ROSE}1${RESET}  Listar cuentas"
    echo -e "  ${ROSE}2${RESET}  Agregar cuenta"
    echo -e "  ${ROSE}3${RESET}  Eliminar cuenta"
    echo -e "  ${ROSE}4${RESET}  Cambiar contraseña"
    echo ""
    echo -e "  ${DIM}0  Volver${RESET}"
    echo ""
    read -rp "$(echo -e "  ${PINK}❯${RESET} ")" OPCION
    echo ""

    case "$OPCION" in
        1) listar_cuentas ;;
        2) agregar_cuenta ;;
        3) eliminar_cuenta ;;
        4) cambiar_contrasena ;;
        0) exit 0 ;;
        *) err "Opción no válida" ; sleep 1 ;;
    esac
done
