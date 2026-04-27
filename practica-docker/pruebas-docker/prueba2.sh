#!/bin/bash
# ============================================================
# Prueba 10.2 — Aislamiento de red y resolución por nombre
# ============================================================
# Demuestra que los contenedores se ven entre sí por nombre
# dentro de la red personalizada infra_red (172.20.0.0/16).
# ============================================================

source "$(dirname "$0")/lib-mensajes.sh"

titulo "Prueba 10.2 · Aislamiento de red"

paso 1 "Ping desde el web hacia la base de datos por nombre"
nota "    (usamos 'db', no una IP)"
docker exec infra_web ping -c 4 db
espaciado

paso 2 "Verificamos la subred personalizada"
docker network inspect infra_red | grep -E "Subnet|Gateway"
espaciado

paso 3 "Listamos los contenedores conectados a la red"
docker network inspect infra_red --format \
    '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}'
espaciado

paso 4 "Probamos el sentido inverso (db hacia web)"
docker exec infra_db ping -c 3 web

fin "prueba 10.2" \
    "La resolución por nombre y la subred 172.20.0.0/16 funcionan correctamente."
