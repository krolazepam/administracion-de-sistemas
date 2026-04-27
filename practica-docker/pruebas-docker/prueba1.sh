#!/bin/bash
# ============================================================
# Prueba 10.1 — Persistencia de la base de datos
# ============================================================
# Demuestra que el volumen db_data conserva los datos
# aunque destruyamos el contenedor de PostgreSQL.
# ============================================================

source "$(dirname "$0")/lib-mensajes.sh"

titulo "Prueba 10.1 · Persistencia de la base de datos"

paso 1 "Insertamos un usuario de prueba"
docker exec infra_db psql -U dualy -d prueba1 -c \
    "INSERT INTO usuarios (nombre, email, password) VALUES ('Prueba Persistencia', 'persist@test.com', 'hash_test');"
espaciado

paso 2 "Listamos los usuarios actuales"
docker exec infra_db psql -U dualy -d prueba1 -c \
    "SELECT id, nombre, email FROM usuarios;"
espaciado

paso 3 "Destruimos el contenedor de la base de datos"
docker rm -f infra_db
espaciado

paso 4 "Confirmamos que ya no existe"
docker compose ps
espaciado

paso 5 "Levantamos un contenedor nuevo"
( cd .. && docker compose up -d db )
nota "    esperando 8 segundos a que arranque..."
sleep 8
espaciado

paso 6 "Verificamos si los datos sobrevivieron"
docker exec infra_db psql -U dualy -d prueba1 -c \
    "SELECT id, nombre, email FROM usuarios;"

fin "prueba 10.1" \
    "Si 'Prueba Persistencia' aparece en el paso 6, el volumen db_data está cumpliendo su función."
