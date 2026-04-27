#!/bin/bash
# ============================================================
# Prueba 10.4 — Límites de recursos
# ============================================================
# Demuestra que cada contenedor tiene límites de RAM y CPU
# para evitar que un proceso descontrolado afecte al resto.
# ============================================================

source "$(dirname "$0")/lib-mensajes.sh"

readonly CONTENEDORES=("infra_web" "infra_db" "infra_ftp" "infra_backup")

titulo "Prueba 10.4 · Límites de recursos"

paso 1 "Vista general con docker stats"
docker stats --no-stream
espaciado

paso 2 "Tabla resumida (nombre, CPU, memoria)"
docker stats --no-stream --format \
    "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
espaciado

paso 3 "Límites configurados a nivel kernel"
 
for contenedor in infra_web infra_db infra_ftp infra_backup; do
    nota "    ── ${contenedor} ──"
 
    mem_bytes=$(docker inspect --format='{{.HostConfig.Memory}}' ${contenedor})
    mem_reserva=$(docker inspect --format='{{.HostConfig.MemoryReservation}}' ${contenedor})
    cpu_nano=$(docker inspect --format='{{.HostConfig.NanoCpus}}' ${contenedor})
 
    mem_mib=$(( mem_bytes / 1048576 ))
    reserva_mib=$(( mem_reserva / 1048576 ))
    cpu_milicores=$(( cpu_nano / 1000000 ))
 
    echo "    Memoria limite:   ${mem_mib} MiB (${mem_bytes} bytes)"
    echo "    Memoria reserva:  ${reserva_mib} MiB (${mem_reserva} bytes)"
    echo "    CPU asignados:    ${cpu_milicores} milicores (${cpu_nano} nanoCPUs)"
    espaciado
done

fin "prueba 10.4" \
    "Los límites de memoria y CPU están configurados. Un proceso descontrolado no puede afectar al resto."
