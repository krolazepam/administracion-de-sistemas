# ============================================================
# Dockerfile personalizado - Servidor FTP (pure-ftpd)
# ============================================================
# Base: alpine (ligera)
# Permite carga de archivos al volumen compartido web_content
# ============================================================

FROM alpine:3.19

LABEL maintainer="practica-docker"
LABEL description="Servidor FTP con pure-ftpd sobre Alpine"

# Instalar pure-ftpd y utilidades mínimas
RUN apk add --no-cache \
        pure-ftpd \
        bash \
        shadow && \
    # Crear directorio de trabajo
    mkdir -p /home/ftpuser && \
    # Crear directorio para configuración de usuarios virtuales
    mkdir -p /etc/pure-ftpd/passwd

# Script de arranque que crea el usuario virtual con las env vars
COPY start-ftp.sh /usr/local/bin/start-ftp.sh
RUN chmod +x /usr/local/bin/start-ftp.sh

# Puerto de control + rango pasivo
EXPOSE 21 30000-30009

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD netstat -ln | grep -q ":21 " || exit 1

ENTRYPOINT ["/usr/local/bin/start-ftp.sh"]
