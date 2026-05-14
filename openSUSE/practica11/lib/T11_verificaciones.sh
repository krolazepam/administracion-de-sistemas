#!/bin/bash

verificar_docker_compose() {
    print_info "[INFO] Verificando Docker Compose..."

    if docker compose version &>/dev/null; then
        print_completado "[OK] Docker Compose plugin: $(docker compose version --short 2>/dev/null)"
        COMPOSE_CMD="docker compose"
        return
    fi

    if command -v docker-compose &>/dev/null; then
        print_completado "[OK] docker-compose: $(docker-compose --version 2>/dev/null)"
        COMPOSE_CMD="docker-compose"
        return
    fi

    print_info "[INFO] Intentando instalar docker-compose via zypper..."
    sudo zypper install -y docker-compose &>/dev/null
    hash -r 2>/dev/null

    if command -v docker-compose &>/dev/null; then
        print_completado "[OK] docker-compose instalado via zypper"
        COMPOSE_CMD="docker-compose"
        return
    fi

    print_info "[INFO] Descargando docker-compose desde GitHub..."
    local version
    version=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)

    if [ -z "$version" ]; then
        print_error "[ERROR] No se pudo obtener la version de docker-compose"
        exit 1
    fi

    local url="https://github.com/docker/compose/releases/download/${version}/docker-compose-$(uname -s)-$(uname -m)"
    if sudo curl -fsSL "$url" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose; then
        hash -r 2>/dev/null
        print_completado "[OK] docker-compose $version instalado en /usr/local/bin"
        COMPOSE_CMD="docker-compose"
    else
        print_error "[ERROR] No se pudo instalar Docker Compose"
        exit 1
    fi
}

verificar_dependencias() {
    print_titulo "Verificando dependencias"
    verificar_docker
    verificar_servicio_docker
    verificar_grupo_docker
    verificar_docker_compose
}
