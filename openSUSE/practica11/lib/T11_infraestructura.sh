#!/bin/bash

# Archivos montados en contenedores van a /opt/t11/ (world-accessible)
# .env y docker-compose.yml se quedan en el directorio del repo (los lee el host)
DOCKER_ASSETS="/opt/t11"

crear_env() {
    local dir="$1"
    local env_file="$dir/.env"

    if [ -f "$env_file" ]; then
        print_completado "[OK] Archivo .env ya existe"
        return
    fi

    print_info "[INFO] Creando archivo .env..."
    cat > "$env_file" << 'EOF'
# Base de datos PostgreSQL
DB_USER=admin
DB_PASS=cambiar_en_produccion
DB_NAME=appdb

# pgAdmin
PGADMIN_EMAIL=admin@local.com
PGADMIN_PASS=cambiar_en_produccion

# Puerto local para pgAdmin (solo accesible desde localhost via tunel SSH)
PGADMIN_PORT=5050
EOF
    chmod 600 "$env_file"
    print_completado "[OK] Archivo .env creado"
    print_info "[AVISO] Edita $env_file con tus credenciales antes de levantar el stack"
}

crear_nginx_conf() {
    local conf_file="$DOCKER_ASSETS/nginx.conf"

    if [ -f "$conf_file" ]; then
        print_completado "[OK] nginx.conf ya existe"
        return
    fi

    print_info "[INFO] Creando nginx.conf en $DOCKER_ASSETS..."
    sudo mkdir -p "$DOCKER_ASSETS"
    sudo chmod 755 "$DOCKER_ASSETS"

    sudo tee "$conf_file" > /dev/null << 'EOF'
user  nginx;
worker_processes  auto;

events {
    worker_connections  1024;
}

http {
    server_tokens off;

    upstream app_backend {
        server app_interna:80;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass         http://app_backend;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_hide_header  X-Powered-By;
        }
    }
}
EOF
    sudo chmod 644 "$conf_file"
    print_completado "[OK] nginx.conf creado"
}

crear_html_app() {
    local html_dir="$DOCKER_ASSETS/html"

    sudo mkdir -p "$html_dir"
    sudo chmod 755 "$html_dir"

    if [ -f "$html_dir/index.html" ]; then
        print_completado "[OK] HTML de app interna ya existe"
        return
    fi

    print_info "[INFO] Creando pagina de app interna (Apache httpd)..."
    sudo tee "$html_dir/index.html" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>App Interna - Tarea 11</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: Arial, sans-serif;
            background: #1a1a2e;
            color: #eee;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
        }
        .card {
            background: #16213e;
            padding: 2rem 2.5rem;
            border-radius: 8px;
            border-left: 4px solid #e94560;
            max-width: 520px;
            width: 90%;
        }
        h1 { color: #e94560; margin-bottom: 1rem; }
        p { margin-bottom: 0.75rem; line-height: 1.5; }
        .badge {
            display: inline-block;
            background: #0f3460;
            padding: 3px 10px;
            border-radius: 4px;
            font-size: 0.8rem;
            margin-right: 6px;
            margin-top: 0.5rem;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>App Interna</h1>
        <p>Servicio corriendo en <strong>Apache httpd</strong>.</p>
        <p>Este contenedor <strong>no tiene puertos expuestos</strong> al host.</p>
        <p>Accesible unicamente a traves del balanceador <strong>Nginx</strong>.</p>
        <div>
            <span class="badge">red_publica</span>
            <span class="badge">httpd:alpine</span>
        </div>
    </div>
</body>
</html>
EOF
    sudo chmod 644 "$html_dir/index.html"
    print_completado "[OK] Pagina de app interna creada"
}

crear_docker_compose() {
    local dir="$1"
    local compose_file="$dir/docker-compose.yml"

    if [ -f "$compose_file" ]; then
        print_completado "[OK] docker-compose.yml ya existe"
        return
    fi

    print_info "[INFO] Creando docker-compose.yml..."
    cat > "$compose_file" << 'EOF'
services:

  nginx:
    image: nginx:alpine
    container_name: t11_nginx
    ports:
      - "80:80"
    volumes:
      - /opt/t11/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - red_publica
      - red_datos
    restart: always
    depends_on:
      - app_interna

  app_interna:
    image: httpd:alpine
    container_name: t11_app
    volumes:
      - /opt/t11/html:/usr/local/apache2/htdocs:ro
    networks:
      - red_publica
    restart: always

  postgresql:
    image: postgres:16-alpine
    container_name: t11_db
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - t11_db_data:/var/lib/postgresql/data
    networks:
      - red_datos
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  pgadmin:
    image: dpage/pgadmin4
    container_name: t11_pgadmin
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASS}
    ports:
      - "127.0.0.1:${PGADMIN_PORT:-5050}:80"
    networks:
      - red_datos
    restart: always
    depends_on:
      postgresql:
        condition: service_healthy

networks:
  red_publica:
    driver: bridge
  red_datos:
    driver: bridge

volumes:
  t11_db_data:
    name: t11_db_data
EOF
    print_completado "[OK] docker-compose.yml creado"
}

crear_infraestructura() {
    local dir="$1"
    print_titulo "Generando archivos de infraestructura"
    crear_env "$dir"
    crear_nginx_conf
    crear_html_app
    crear_docker_compose "$dir"
}
