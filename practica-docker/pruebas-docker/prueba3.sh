#!/bin/bash
# ============================================================
# Prueba 10.3 — Permisos FTP y volumen compartido
# ============================================================
# Demuestra que el volumen web_content es compartido entre
# el FTP y el WEB. Lo que se sube por FTP, el web lo sirve.
# ============================================================

source "$(dirname "$0")/lib-mensajes.sh"

readonly ARCHIVO_PRUEBA="prueba-ftp.html"

titulo "Prueba 10.3 · Permisos FTP y volumen compartido"

paso 1 "Creamos un archivo de prueba en el host"
echo "<h1>Archivo subido por FTP - $(date '+%Y-%m-%d %H:%M:%S')</h1>" > "$ARCHIVO_PRUEBA"
cat "$ARCHIVO_PRUEBA"
espaciado

paso 2 "Lo subimos por FTP con el usuario ftpuser"
if curl -T "$ARCHIVO_PRUEBA" ftp://localhost/ --user dualy:snowy180405 -s -S; then
    nota "    archivo subido correctamente."
fi
espaciado

paso 3 "Verificamos que está dentro del contenedor FTP"
docker exec infra_ftp ls -la /home/ftpuser/$ARCHIVO_PRUEBA
espaciado

paso 4 "Verificamos que el web también lo ve"
nota "    (mismo volumen web_content compartido)"
docker exec infra_web ls -la /usr/share/nginx/html/$ARCHIVO_PRUEBA
espaciado

paso 5 "Lo accedemos vía HTTP"
nota "    petición a http://localhost:8080/$ARCHIVO_PRUEBA :"
curl -s http://localhost:8080/$ARCHIVO_PRUEBA
espaciado
espaciado

paso 6 "Inspeccionamos el volumen web_content"
docker volume inspect web_content --format \
    'Volumen: {{.Name}}{{"\n"}}Driver:  {{.Driver}}{{"\n"}}Ruta:    {{.Mountpoint}}'

# Limpieza local
rm -f "$ARCHIVO_PRUEBA"

fin "prueba 10.3" \
    "El archivo se subió por FTP y el web lo sirvió enseguida. Volumen compartido funcionando."
