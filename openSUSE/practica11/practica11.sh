#!/bin/bash

MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$MAIN_DIR/lib"
COMPOSE_DIR="$MAIN_DIR"

source "$LIB/colores.sh"
source "$LIB/docker_install.sh"
source "$LIB/T11_verificaciones.sh"
source "$LIB/T11_infraestructura.sh"
source "$LIB/T11_firewall.sh"
source "$LIB/T11_stack.sh"
source "$LIB/T11_pruebas.sh"

# Detectar docker compose al arrancar para que -v/-s/-u/-r funcionen
# sin necesitar pasar por -i primero
_detectar_compose_cmd() {
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
}
_detectar_compose_cmd

# ─────────────────────────────────────────────────────────────────────────────

instalar() {
    print_titulo "Tarea 11 - Instalacion completa"
    verificar_dependencias
    crear_infraestructura "$COMPOSE_DIR"
    configurar_firewall_t11
    levantar_stack "$COMPOSE_DIR"
    print_titulo "Instalacion finalizada"
    estado_stack "$COMPOSE_DIR"
}

verificar() {
    estado_stack "$COMPOSE_DIR"
}

detener() {
    print_titulo "Deteniendo stack"
    detener_stack "$COMPOSE_DIR"
}

iniciar() {
    print_titulo "Iniciando stack"
    levantar_stack "$COMPOSE_DIR"
}

resetear() {
    print_titulo "Reseteo completo"
    print_info "[INFO] Esto eliminara contenedores, redes y volumenes de datos"
    read -p "  Estas seguro? (s/N): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        resetear_stack "$COMPOSE_DIR"
    else
        print_info "[INFO] Operacion cancelada"
    fi
}

pruebas() {
    ejecutar_pruebas
}

ayuda() {
    print_titulo "Tarea 11 - Orquestacion de Microservicios"
    echo -e "  ${verde}-i${nc}   Instalar dependencias, generar archivos y levantar el stack"
    echo -e "  ${verde}-v${nc}   Verificar estado de contenedores y redes"
    echo -e "  ${verde}-s${nc}   Detener el stack (conserva datos)"
    echo -e "  ${verde}-u${nc}   Iniciar stack previamente detenido"
    echo -e "  ${verde}-r${nc}   Resetear todo (elimina contenedores y volumenes)"
    echo -e "  ${verde}-p${nc}   Ejecutar protocolo de pruebas de aceptacion (4 pruebas)"
    echo -e "  ${verde}-h${nc}   Mostrar esta ayuda"
    echo ""
    echo -e "  ${azul}Servicios desplegados:${nc}"
    echo -e "    nginx        Puerto 80          Balanceador / punto de entrada publico"
    echo -e "    app_interna  (sin puertos)       Apache httpd, solo via nginx"
    echo -e "    postgresql   (sin puertos)       Base de datos, red interna red_datos"
    echo -e "    pgadmin      127.0.0.1:5050      Panel admin, solo via tunel SSH"
    echo ""
    echo -e "  ${azul}Redes internas:${nc}"
    echo -e "    red_publica  nginx + app_interna"
    echo -e "    red_datos    postgresql + pgadmin  (aislada del exterior)"
    echo ""
    echo -e "  ${azul}Acceso a pgAdmin via tunel SSH:${nc}"
    local ip
    ip=$(ip addr show enp0s9 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    echo -e "    ssh -L 8080:localhost:5050 ${USER}@${ip:-<ip_servidor>}"
    echo -e "    Luego abrir http://localhost:8080 en el navegador"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
    ayuda
    exit 0
fi

while getopts "ivsurhp" opt; do
    case $opt in
        i) instalar ;;
        v) verificar ;;
        s) detener ;;
        u) iniciar ;;
        r) resetear ;;
        p) pruebas ;;
        h) ayuda ;;
        *) print_error "[ERROR] Opcion invalida. Usa -h para ver la ayuda" ; exit 1 ;;
    esac
done
