# Práctica: Migración de servicios esenciales a contenedores

Infraestructura dockerizada con 4 servicios: servidor web (Nginx Alpine), base de datos (PostgreSQL), servidor FTP (pure-ftpd) y servicio de respaldo automatizado. Todos conectados por una red bridge personalizada con subred `172.20.0.0/16`, volúmenes persistentes y límites de recursos.

---

## Estructura del proyecto

```
practica-docker/
├── docker-compose.yml      # Orquestación de los 4 servicios
├── .env.example            # Variables de entorno (copiar a .env)
├── README.md               # Este archivo
├── backups/                # Respaldos automáticos (bind mount al host)
│
├── web/                    # Servidor Nginx (Dockerfile personalizado)
│   ├── Dockerfile
│   ├── nginx.conf          # server_tokens off + hardening
│   └── html/               # Contenido estático
│       ├── index.html
│       ├── styles.css
│       └── images/logo.svg
│
├── db/                     # PostgreSQL
│   ├── Dockerfile
│   └── init/01-init.sql    # Tabla usuarios + datos de ejemplo
│
├── ftp/                    # Servidor FTP pure-ftpd
│   ├── Dockerfile
│   └── start-ftp.sh
│
└── backup/                 # Sidecar de respaldo automatizado
    ├── Dockerfile
    ├── entrypoint.sh
    └── backup.sh
```

---

## Requisitos cubiertos

| Requerimiento | Dónde se implementa |
|---|---|
| Servidor web basado en imagen ligera (Alpine) | `web/Dockerfile` → `nginx:1.27-alpine` |
| Imagen personalizada (no descarga directa) | `web/Dockerfile` con build context propio |
| Consume recursos estáticos (CSS + imagen) | `web/html/styles.css`, `web/html/images/logo.svg` |
| PostgreSQL con datos de usuarios | `db/init/01-init.sql` |
| Respaldo automatizado al host | Servicio `backup` + bind mount `./backups` |
| Servidor FTP para carga de instaladores | Servicio `ftp` (pure-ftpd) |
| Red personalizada `172.20.0.0/16` | Red `infra_red` en `docker-compose.yml` |
| Límite de RAM (512MB) y CPU | `mem_limit` y `cpus` por servicio |
| Eliminar firmas del servidor (server tokens) | `server_tokens off` en `nginx.conf` |
| Usuario no-administrativo | `webuser` (UID 1001) en `web/Dockerfile` |
| Volumen `db_data` para PostgreSQL | Volumen nombrado en compose |
| Volumen `web_content` para contenido web | Compartido entre `web` y `ftp` |
| Red `infra_red` con resolución por nombre | Bridge personalizada |

---

## Despliegue

### 1. Preparar variables de entorno

```bash
cp .env.example .env
# Edita .env con tus credenciales (opcional)
```

### 2. Construir y levantar todos los servicios

```bash
docker compose up -d --build
```

### 3. Verificar que todo está corriendo

```bash
docker compose ps
```

Deberías ver 4 contenedores en estado `Up`: `infra_web`, `infra_db`, `infra_ftp`, `infra_backup`.

### 4. Acceder a los servicios

| Servicio | URL / Conexión |
|---|---|
| Web | http://localhost:8080 |
| PostgreSQL | `localhost:5432` — solo accesible desde la red `infra_red` (por diseño) |
| FTP | `ftp://localhost:21` (usuario: `ftpuser` / pass: `ftppass123`) |
| Backups | carpeta `./backups/` en el host |

> **Nota para Windows:** Si usas Docker Desktop con WSL2, todos los comandos funcionan igual desde PowerShell o desde la terminal WSL. Los bind mounts (`./backups`) se mapean automáticamente a la ruta de Windows.

---

## Protocolo de pruebas (validación)

### Prueba 10.1 — Persistencia de BD

Verifica que los datos sobrevivan a la destrucción del contenedor gracias al volumen `db_data`.

```bash
# 1) Crear una base de datos nueva y agregar datos
docker exec -it infra_db psql -U appuser -d appdb -c \
    "INSERT INTO usuarios (nombre, email, password) VALUES ('Prueba Persistencia', 'persist@test.com', 'hash');"

# 2) Verificar que el registro existe
docker exec -it infra_db psql -U appuser -d appdb -c \
    "SELECT * FROM usuarios WHERE email='persist@test.com';"

# 3) DESTRUIR el contenedor (el volumen db_data SOBREVIVE)
docker rm -f infra_db

# 4) Levantar un contenedor nuevo
docker compose up -d db

# 5) Verificar que el dato sigue ahí
docker exec -it infra_db psql -U appuser -d appdb -c \
    "SELECT * FROM usuarios WHERE email='persist@test.com';"
```

**Resultado esperado:** el registro `persist@test.com` aparece antes y después del `docker rm -f`.

---

### Prueba 10.2 — Aislamiento de red y resolución por nombre

Verifica que los contenedores se ven entre sí por nombre de servicio dentro de `infra_red`.

```bash
# Ping desde el contenedor web al contenedor db POR NOMBRE
docker exec -it infra_web ping -c 4 db

# Verificar que la red tiene la subred correcta
docker network inspect infra_red | grep -A 2 "Subnet"
```

**Resultado esperado:** 4 paquetes recibidos desde `172.20.0.20` (IP de `db`). La subred debe mostrar `172.20.0.0/16`.

Adicional (opcional, para demostrar aislamiento):

```bash
# Verificar que el contenedor de BD NO está expuesto al host
# (no debería haber puerto 5432 mapeado)
docker compose ps db
# Intentar conexión desde el host debería fallar
```

---

### Prueba 10.3 — Permisos FTP y volumen compartido

Sube un archivo vía FTP y verifica que el servidor web puede servirlo desde el mismo volumen `web_content`.

**Opción A — cliente `ftp` de línea de comandos:**

```bash
# Crear archivo de prueba
echo "<h1>Subido por FTP</h1>" > prueba-ftp.html

# Conectarse y subir
ftp -n -p localhost <<EOF
user ftpuser ftppass123
put prueba-ftp.html
bye
EOF
```

**Opción B — con `curl`:**

```bash
echo "<h1>Subido por FTP</h1>" > prueba-ftp.html
curl -T prueba-ftp.html ftp://localhost/ --user ftpuser:ftppass123
```

**Opción C — cliente gráfico:** FileZilla apuntando a `localhost:21`, modo pasivo, usuario `ftpuser` / pass `ftppass123`.

**Verificación desde el web:**

```bash
# El archivo debe estar accesible vía HTTP inmediatamente
curl http://localhost:8080/prueba-ftp.html
```

**Resultado esperado:** `curl` devuelve `<h1>Subido por FTP</h1>`.

---

### Prueba 10.4 — Límites de recursos

```bash
docker stats --no-stream
```

**Resultado esperado:** la columna `MEM USAGE / LIMIT` muestra `/ 512MiB` para `infra_web` e `infra_db`, `/ 256MiB` para `infra_ftp`, y `/ 128MiB` para `infra_backup`. La columna `CPU %` respeta los límites configurados.

Para ver el detalle en formato más claro:

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## Prueba extra — Respaldo automatizado

```bash
# Forzar un respaldo manual inmediato (sin esperar al cron)
docker exec -it infra_backup /usr/local/bin/backup.sh

# Ver los respaldos generados en el host
ls -lh backups/
```

**Resultado esperado:** archivo `appdb_YYYYMMDD_HHMMSS.sql.gz` en `./backups/`. La rotación mantiene los últimos 7.

Para ver el cron activo:

```bash
docker exec -it infra_backup crontab -l
```

---

## Verificación del hardening del servidor web

```bash
# Confirmar que server_tokens está desactivado (no debe aparecer versión)
curl -I http://localhost:8080

# Confirmar que nginx corre como webuser, no como root
docker exec -it infra_web ps aux | head
```

**Resultado esperado:** el header `Server:` no incluye número de versión, y el proceso `nginx: worker` corre como `webuser`.

---

## Comandos útiles

```bash
# Ver logs de un servicio
docker compose logs -f web
docker compose logs -f backup

# Reiniciar un servicio
docker compose restart web

# Detener todo (conserva volúmenes)
docker compose down

# Detener todo Y BORRAR volúmenes (¡pierde datos!)
docker compose down -v

# Reconstruir solo una imagen
docker compose build web
docker compose up -d web
```

---

## Decisiones de diseño

1. **Nginx en vez de Apache:** más fácil correr como no-root y la directiva `server_tokens off` es más directa.
2. **pure-ftpd:** ligero en Alpine, soporta usuarios virtuales (no modifica `/etc/passwd`).
3. **Puerto 8080 (no 80) en el web:** un usuario no-root no puede bindear puertos privilegiados (<1024).
4. **PostgreSQL sin puerto expuesto al host:** solo accesible desde `infra_red`, reduciendo superficie de ataque.
5. **Backup en contenedor separado:** principio de mínimo privilegio — el contenedor de BD no necesita tener cron ni utilidades extra.
6. **Bind mount para backups:** el enunciado pide "carpeta del host", y un bind mount es más directo que un volumen nombrado para este caso.
