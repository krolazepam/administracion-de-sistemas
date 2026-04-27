#!/bin/bash
# ============================================================
# lib-mensajes.sh
# ============================================================
# Funciones reutilizables para imprimir mensajes con colores
# de forma consistente en todas las pruebas.
#
# Uso desde otro script:
#   source ./lib-mensajes.sh
#   titulo "Prueba 10.X · Descripción"
#   paso 1 "Hacemos esto"
#   nota "Aclaración secundaria"
#   fin "Mensaje de cierre"
# ============================================================

# Paleta de colores (códigos ANSI)
readonly COLOR_TITULO='\033[0;36m'    # cyan
readonly COLOR_OK='\033[0;32m'        # verde
readonly COLOR_PASO='\033[0;90m'      # gris
readonly COLOR_NOTA='\033[0;90m'      # gris
readonly COLOR_RESET='\033[0m'

# ------------------------------------------------------------
# titulo: encabezado de la prueba
#   Uso:  titulo "Prueba 10.1 · Persistencia"
# ------------------------------------------------------------
titulo() {
    local texto="$1"
    echo ""
    echo -e "${COLOR_TITULO}── ${texto} ──${COLOR_RESET}"
    echo ""
}

# ------------------------------------------------------------
# paso: enuncia un paso numerado
#   Uso:  paso 1 "Insertamos un usuario"
# ------------------------------------------------------------
paso() {
    local numero="$1"
    local descripcion="$2"
    echo -e "${COLOR_PASO}Paso ${numero} · ${descripcion}${COLOR_RESET}"
}

# ------------------------------------------------------------
# nota: aclaración o comentario en gris
#   Uso:  nota "    (no usamos IP, usamos el nombre 'db')"
# ------------------------------------------------------------
nota() {
    local texto="$1"
    echo -e "${COLOR_NOTA}${texto}${COLOR_RESET}"
}

# ------------------------------------------------------------
# fin: cierre de la prueba con mensaje de éxito
#   Uso:  fin "Prueba 10.1" "El volumen está bien."
# ------------------------------------------------------------
fin() {
    local nombre="$1"
    local mensaje="$2"
    echo ""
    echo -e "${COLOR_OK}── Fin de la ${nombre} ──${COLOR_RESET}"
    [ -n "$mensaje" ] && nota "${mensaje}"
    echo ""
}

# ------------------------------------------------------------
# espaciado: salto de línea simple (azúcar sintáctica)
# ------------------------------------------------------------
espaciado() {
    echo ""
}
