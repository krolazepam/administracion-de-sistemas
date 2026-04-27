# ============================================================
# Dockerfile personalizado - Servidor Web Nginx
# ============================================================
# Requisitos cubiertos:
#  - Imagen ligera (alpine)
#  - server_tokens off (ocultar firma del servidor)
#  - Ejecuta como usuario no-administrativo (webuser, UID 1001)
#  - Contenido estático personalizado (html + css + imagen)
# ============================================================

FROM nginx:1.27-alpine

LABEL maintainer="practica-docker"
LABEL description="Servidor web endurecido - usuario no-root y sin server tokens"

# 1) Reemplazar configuración por defecto con la endurecida
COPY nginx.conf /etc/nginx/nginx.conf

# 2) Copiar contenido estático al document root
COPY html/ /usr/share/nginx/html/

# 3) Crear grupo y usuario no-privilegiado
RUN addgroup -g 1001 -S webgroup && \
    adduser  -u 1001 -S webuser -G webgroup

# 4) Ajustar permisos para que nginx pueda correr como webuser
#    (directorios de caché, logs, pid y contenido)
RUN mkdir -p /var/cache/nginx /var/run /var/log/nginx && \
    chown -R webuser:webgroup \
        /var/cache/nginx \
        /var/log/nginx \
        /etc/nginx/conf.d \
        /usr/share/nginx/html && \
    touch /var/run/nginx.pid && \
    chown webuser:webgroup /var/run/nginx.pid && \
    # Eliminar archivo de versión expuesto en algunas rutas
    rm -f /usr/share/nginx/html/50x.html

# 5) Cambiar a usuario no-privilegiado
USER webuser

# 6) Exponer puerto no-privilegiado (no root -> no puede bindear 80)
EXPOSE 8080

# 7) Healthcheck simple
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --spider http://localhost:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
