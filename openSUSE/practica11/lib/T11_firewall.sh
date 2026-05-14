#!/bin/bash

configurar_firewall_t11() {
    print_titulo "Configurando firewall"

    if ! command -v firewall-cmd &>/dev/null; then
        print_info "[INFO] firewalld no encontrado, omitiendo configuracion"
        return
    fi

    if ! systemctl is-active --quiet firewalld; then
        print_info "[INFO] Iniciando firewalld..."
        sudo systemctl enable firewalld &>/dev/null
        sudo systemctl start firewalld
    fi

    # SSH siempre abierto (unico vector de acceso a servicios internos)
    sudo firewall-cmd --permanent --add-service=ssh &>/dev/null

    # Puerto 80 abierto para nginx (unico punto de entrada publico)
    sudo firewall-cmd --permanent --add-port=80/tcp &>/dev/null
    print_completado "[OK] Puerto 80 (nginx) abierto"

    # Bloquear pgAdmin: vinculado a 127.0.0.1 en compose, pero se cierra
    # explicitamente en firewall para demostrar defensa en profundidad
    sudo firewall-cmd --permanent --remove-port=5050/tcp &>/dev/null
    print_completado "[OK] Puerto 5050 (pgAdmin) bloqueado externamente"

    # Bloquear PostgreSQL: no tiene mapeo de puertos al host, pero se
    # cierra 5432 por si otra instancia estuviera expuesta
    sudo firewall-cmd --permanent --remove-port=5432/tcp &>/dev/null
    print_completado "[OK] Puerto 5432 (PostgreSQL) bloqueado externamente"

    sudo firewall-cmd --reload &>/dev/null
    print_completado "[OK] Reglas de firewall aplicadas"
    echo ""
    print_info "[INFO] Acceso a pgAdmin SOLO via tunel SSH:"
    print_info "       ssh -L 8080:localhost:5050 usuario@ip_servidor"
    print_info "       Luego abrir: http://localhost:8080"
}
