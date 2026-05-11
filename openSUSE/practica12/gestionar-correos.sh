#!/bin/bash

DOMINIO="reprobados.com"

listar_cuentas() {
    echo ""
    echo "  Cuentas existentes:"
    docker exec mailserver setup email list 2>/dev/null | \
        sed 's/^/    /' || echo "    (no se pudo obtener la lista)"
    echo ""
}

agregar_cuenta() {
    listar_cuentas

    while true; do
        read -rp "  Usuario (sin @$DOMINIO): " USUARIO
        if [[ -z "$USUARIO" ]]; then
            echo "  [ERROR] El usuario no puede estar vacío"
            continue
        fi
        if [[ ! "$USUARIO" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo "  [ERROR] El usuario solo puede contener letras, números, puntos, guiones y guiones bajos"
            continue
        fi
        break
    done

    EMAIL="${USUARIO}@${DOMINIO}"

    if docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        echo "  [WARN] La cuenta $EMAIL ya existe"
        return
    fi

    while true; do
        read -rsp "  Contraseña: " PASS; echo
        if [[ -z "$PASS" ]]; then
            echo "  [ERROR] La contraseña no puede estar vacía"
            continue
        fi
        read -rsp "  Confirmar contraseña: " PASS2; echo
        if [[ "$PASS" != "$PASS2" ]]; then
            echo "  [ERROR] Las contraseñas no coinciden, intenta de nuevo"
            continue
        fi
        break
    done

    if docker exec mailserver setup email add "$EMAIL" "$PASS" 2>/dev/null; then
        echo "  [OK] Cuenta $EMAIL creada exitosamente"
    else
        echo "  [ERROR] No se pudo crear la cuenta"
    fi
}

eliminar_cuenta() {
    listar_cuentas

    read -rp "  Usuario a eliminar (sin @$DOMINIO): " USUARIO
    EMAIL="${USUARIO}@${DOMINIO}"

    if ! docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        echo "  [ERROR] La cuenta $EMAIL no existe"
        return
    fi

    read -rp "  ¿Confirmas eliminar $EMAIL? (s/N): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "  [Cancelado]"
        return
    fi

    if docker exec mailserver setup email del "$EMAIL" 2>/dev/null; then
        echo "  [OK] Cuenta $EMAIL eliminada"
    else
        echo "  [ERROR] No se pudo eliminar la cuenta"
    fi
}

cambiar_contrasena() {
    listar_cuentas

    read -rp "  Usuario (sin @$DOMINIO): " USUARIO
    EMAIL="${USUARIO}@${DOMINIO}"

    if ! docker exec mailserver setup email list 2>/dev/null | grep -q "^${EMAIL}"; then
        echo "  [ERROR] La cuenta $EMAIL no existe"
        return
    fi

    while true; do
        read -rsp "  Nueva contraseña: " PASS; echo
        if [[ -z "$PASS" ]]; then
            echo "  [ERROR] La contraseña no puede estar vacía"
            continue
        fi
        read -rsp "  Confirmar contraseña: " PASS2; echo
        if [[ "$PASS" != "$PASS2" ]]; then
            echo "  [ERROR] Las contraseñas no coinciden, intenta de nuevo"
            continue
        fi
        break
    done

    if docker exec mailserver setup email update "$EMAIL" "$PASS" 2>/dev/null; then
        echo "  [OK] Contraseña de $EMAIL actualizada"
    else
        echo "  [ERROR] No se pudo actualizar la contraseña"
    fi
}

# Menú principal
while true; do
    echo ""
    echo "======================================================"
    echo "  Gestión de correos — $DOMINIO"
    echo "======================================================"
    echo "  1) Listar cuentas"
    echo "  2) Agregar cuenta"
    echo "  3) Eliminar cuenta"
    echo "  4) Cambiar contraseña"
    echo "  5) Salir"
    echo "======================================================"
    read -rp "  Opción: " OPCION
    echo ""

    case "$OPCION" in
        1) listar_cuentas ;;
        2) agregar_cuenta ;;
        3) eliminar_cuenta ;;
        4) cambiar_contrasena ;;
        5) echo "  Hasta luego."; exit 0 ;;
        *) echo "  [ERROR] Opción inválida" ;;
    esac
done
