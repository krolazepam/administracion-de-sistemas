#!/bin/bash
# ============================================================
# ejecutar-todas.sh
# ============================================================
# Ejecuta las 4 pruebas en orden, una por una.
# ============================================================

source "$(dirname "$0")/lib-mensajes.sh"

readonly PRUEBAS=("prueba1.sh" "prueba2.sh" "prueba3.sh" "prueba4.sh")

titulo "Pruebas de validación · práctica Docker"
nota "    $(date '+%Y-%m-%d %H:%M:%S')"
espaciado
sleep 1

for i in "${!PRUEBAS[@]}"; do
    sh "$(dirname "$0")/${PRUEBAS[$i]}"

    # Pausa entre pruebas, excepto después de la última
    if [ "$i" -lt $((${#PRUEBAS[@]} - 1)) ]; then
        espaciado
        siguiente=$((i + 2))
        read -p "    presiona ENTER para seguir con la 10.${siguiente}..."
        espaciado
    fi
done

fin "ejecución" "Todas las pruebas terminaron."
