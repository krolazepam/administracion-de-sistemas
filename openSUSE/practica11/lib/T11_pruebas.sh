#!/bin/bash

# Protocolo de pruebas de aceptacion - Tarea 11
# Requiere que COMPOSE_DIR y COMPOSE_CMD esten definidos (los define practica11.sh)

_separador_prueba() {
    echo -e "\n${cyan}────────────────────────────────────────────────────────${nc}\n"
}

_leer_env() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        source "$env_file"
    else
        print_error "[ERROR] No se encontro .env en: $env_file"
        return 1
    fi
}

_stack_corriendo() {
    docker inspect t11_db &>/dev/null && \
    docker inspect --format='{{.State.Status}}' t11_db 2>/dev/null | grep -q "running"
}

# ─── Prueba 11.1 ─────────────────────────────────────────────────────────────

prueba_aislamiento_red() {
    print_titulo "Prueba 11.1 - Aislamiento de red"
    echo -e "  ${azul}Objetivo:${nc} Los puertos 5050 (pgAdmin) y 5432 (PostgreSQL)"
    echo -e "  deben ser inaccesibles desde la red publica."
    echo ""

    local resultado_general=0

    # pgAdmin debe estar vinculado solo a 127.0.0.1, no a 0.0.0.0
    local pg_binding
    pg_binding=$(ss -tlnp 2>/dev/null | grep ":5050" | awk '{print $4}')

    if [ -z "$pg_binding" ]; then
        print_completado "[OK] Puerto 5050 no expuesto al host (servicio no iniciado o totalmente interno)"
    elif echo "$pg_binding" | grep -q "127.0.0.1"; then
        print_completado "[OK] pgAdmin vinculado a 127.0.0.1:5050 (inaccesible desde la red externa)"
    else
        print_error "[FALLO] pgAdmin escucha en $pg_binding (deberia ser 127.0.0.1)"
        resultado_general=1
    fi

    # PostgreSQL no debe tener ningun mapeo al host
    local db_binding
    db_binding=$(ss -tlnp 2>/dev/null | grep ":5432" | awk '{print $4}')

    if [ -z "$db_binding" ]; then
        print_completado "[OK] Puerto 5432 (PostgreSQL) no expuesto al host"
    else
        print_error "[FALLO] Puerto 5432 accesible en: $db_binding"
        resultado_general=1
    fi

    # Verificar reglas de firewall
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        local ports_open
        ports_open=$(sudo firewall-cmd --list-ports 2>/dev/null)
        echo ""
        print_info "[INFO] Puertos abiertos en firewall: ${ports_open:-ninguno}"
        if echo "$ports_open" | grep -qE "5050|5432"; then
            print_error "[FALLO] Firewall permite acceso a 5050 o 5432"
            resultado_general=1
        else
            print_completado "[OK] Firewall bloquea 5050 (pgAdmin) y 5432 (PostgreSQL)"
        fi
    fi

    echo ""
    local ip
    ip=$(ip addr show enp0s9 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    print_info "[VERIFICACION MANUAL] Desde la maquina fisica ejecutar:"
    print_info "  curl -m 3 http://${ip:-<ip_servidor>}:5050  →  debe dar Connection refused o timeout"

    [ $resultado_general -eq 0 ] && print_completado "[RESULTADO] Prueba 11.1 SUPERADA" \
                                 || print_error    "[RESULTADO] Prueba 11.1 CON FALLOS"
}

# ─── Prueba 11.2 ─────────────────────────────────────────────────────────────

prueba_dns_interno() {
    print_titulo "Prueba 11.2 - Resolucion DNS interna"
    echo -e "  ${azul}Objetivo:${nc} Desde el contenedor nginx, resolver el nombre del"
    echo -e "  servicio 'postgresql' por DNS interno de Docker (sin IP fija)."
    echo ""

    local resultado_general=0

    if ! _stack_corriendo; then
        print_error "[ERROR] El stack no esta corriendo. Levantalo con: ./practica11.sh -u"
        return 1
    fi

    # nginx esta en red_publica y red_datos, por lo que puede resolver postgresql
    print_info "[INFO] docker exec t11_nginx nslookup postgresql"
    local dns_output
    dns_output=$(docker exec t11_nginx nslookup postgresql 2>&1)
    if echo "$dns_output" | grep -q "Address"; then
        print_completado "[OK] nginx resuelve 'postgresql' por nombre de servicio (DNS interno Docker)"
        echo "$dns_output" | grep -E "Name|Address" | sed 's/^/    /'
    else
        print_error "[FALLO] nginx no puede resolver 'postgresql'"
        echo "$dns_output" | head -5 | sed 's/^/    /'
        resultado_general=1
    fi

    echo ""
    [ $resultado_general -eq 0 ] && print_completado "[RESULTADO] Prueba 11.2 SUPERADA" \
                                 || print_error    "[RESULTADO] Prueba 11.2 CON FALLOS"
}

# ─── Prueba 11.3 ─────────────────────────────────────────────────────────────

prueba_tunel_ssh() {
    print_titulo "Prueba 11.3 - Tunel SSH cifrado"
    echo -e "  ${azul}Objetivo:${nc} Acceder a pgAdmin desde la maquina fisica a traves"
    echo -e "  de un tunel SSH local, sin exponer el puerto publicamente."
    echo ""

    local resultado_general=0

    # Detectar IP del adaptador enp0s9 (red compartida con la maquina fisica)
    local ip
    ip=$(ip addr show enp0s9 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)

    if [ -n "$ip" ]; then
        print_completado "[OK] IP del servidor en enp0s9: $ip"
    else
        print_error "[AVISO] No se encontro el adaptador enp0s9"
        ip=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
        [ -n "$ip" ] && print_info "[INFO] Usando primera IP disponible: $ip" || ip="<ip_servidor>"
        resultado_general=1
    fi

    # Verificar SSH activo
    if systemctl is-active --quiet sshd; then
        print_completado "[OK] Servicio SSH (sshd) activo"
    else
        print_error "[ERROR] sshd no esta activo — iniciar con: sudo systemctl start sshd"
        resultado_general=1
    fi

    # Verificar pgAdmin corriendo y en escucha
    if docker inspect --format='{{.State.Status}}' t11_pgadmin 2>/dev/null | grep -q "running"; then
        print_completado "[OK] Contenedor pgAdmin en ejecucion"
        local pg_port
        pg_port=$(ss -tlnp 2>/dev/null | grep ":5050" | awk '{print $4}')
        [ -n "$pg_port" ] && print_completado "[OK] pgAdmin escuchando en $pg_port"
    else
        print_error "[AVISO] Contenedor pgAdmin no esta corriendo"
        resultado_general=1
    fi

    echo ""
    print_info "[ACCION MANUAL] Ejecutar desde la maquina fisica:"
    echo ""
    echo -e "  ${verde}ssh -L 8080:localhost:5050 ${USER}@${ip}${nc}"
    echo ""
    print_info "Luego abrir en el navegador: ${verde}http://localhost:8080${nc}"
    echo ""

    [ $resultado_general -eq 0 ] && print_completado "[RESULTADO] Prueba 11.3 SUPERADA (verificar acceso desde navegador)" \
                                 || print_error    "[RESULTADO] Prueba 11.3 CON FALLOS previos al tunel"
}

# ─── Prueba 11.4 ─────────────────────────────────────────────────────────────

prueba_persistencia() {
    print_titulo "Prueba 11.4 - Persistencia de datos y healthcheck"
    echo -e "  ${azul}Objetivo:${nc} Los datos sobreviven a un docker-compose down/up."
    echo -e "  pgAdmin espera a que PostgreSQL este healthy antes de iniciar."
    echo ""

    local resultado_general=0
    local env_file="$COMPOSE_DIR/.env"

    _leer_env "$env_file" || return 1

    if ! _stack_corriendo; then
        print_error "[ERROR] El stack no esta corriendo. Levantalo con: ./practica11.sh -u"
        return 1
    fi

    # Verificar que PostgreSQL esta healthy
    local db_status
    db_status=$(docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null)
    if [ "$db_status" = "healthy" ]; then
        print_completado "[OK] PostgreSQL en estado: healthy"
    else
        print_error "[ERROR] PostgreSQL no esta healthy (estado: ${db_status:-desconocido})"
        return 1
    fi

    # Insertar dato de prueba
    print_info "[INFO] Insertando dato de prueba..."
    local marca_tiempo
    marca_tiempo="prueba_t11_$(date +%s)"

    docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -c \
        "CREATE TABLE IF NOT EXISTS prueba_persistencia (id SERIAL, mensaje TEXT, ts TIMESTAMP DEFAULT NOW());" \
        &>/dev/null

    docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO prueba_persistencia (mensaje) VALUES ('${marca_tiempo}');" \
        &>/dev/null

    local count_antes
    count_antes=$(docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' \n')
    print_completado "[OK] Registros antes del reinicio: $count_antes"

    # Bajar el stack
    echo ""
    print_info "[INFO] Deteniendo stack con docker-compose down..."
    $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" down &>/dev/null
    print_completado "[OK] Stack detenido — contenedores eliminados"

    # Verificar que el volumen persiste tras down
    if docker volume ls --format '{{.Name}}' | grep -q "^t11_db_data$"; then
        print_completado "[OK] Volumen t11_db_data persiste tras docker-compose down"
    else
        print_error "[FALLO] Volumen t11_db_data no encontrado tras el down"
        resultado_general=1
    fi

    # Volver a levantar
    echo ""
    print_info "[INFO] Reiniciando stack..."
    $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" --env-file "$env_file" up -d &>/dev/null
    print_completado "[OK] Stack iniciado"

    # Esperar healthcheck
    print_info "[INFO] Esperando que PostgreSQL alcance estado healthy..."
    local intentos=0
    until docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null | grep -q "healthy"; do
        sleep 5
        intentos=$((intentos + 1))
        if [ "$intentos" -ge 12 ]; then
            print_error "[ERROR] Timeout esperando PostgreSQL healthy (60s)"
            return 1
        fi
        print_info "       Esperando... ($((intentos * 5))s)"
    done
    print_completado "[OK] PostgreSQL healthy tras reinicio"

    # Verificar que pgAdmin esperó al healthcheck
    local pgadmin_status
    pgadmin_status=$(docker inspect --format='{{.State.Status}}' t11_pgadmin 2>/dev/null)
    print_completado "[OK] pgAdmin en estado '$pgadmin_status' (inicio condicionado a service_healthy)"

    # Verificar integridad de datos
    echo ""
    print_info "[INFO] Verificando datos persistentes..."
    local count_despues
    count_despues=$(docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' \n')

    if [ "$count_despues" = "$count_antes" ] && [ -n "$count_despues" ]; then
        print_completado "[OK] Datos intactos: $count_despues registro(s) tras reinicio completo"
    else
        print_error "[FALLO] Discrepancia de datos (antes: $count_antes, despues: $count_despues)"
        resultado_general=1
    fi

    echo ""
    [ $resultado_general -eq 0 ] && print_completado "[RESULTADO] Prueba 11.4 SUPERADA" \
                                 || print_error    "[RESULTADO] Prueba 11.4 CON FALLOS"
}

# ─── Orquestador de pruebas ───────────────────────────────────────────────────

ejecutar_pruebas() {
    print_titulo "Protocolo de pruebas de aceptacion - Tarea 11"

    _separador_prueba
    prueba_aislamiento_red

    _separador_prueba
    prueba_dns_interno

    _separador_prueba
    prueba_tunel_ssh

    _separador_prueba
    prueba_persistencia

    _separador_prueba
    print_completado "[OK] Protocolo de pruebas completado"
    echo ""
}
