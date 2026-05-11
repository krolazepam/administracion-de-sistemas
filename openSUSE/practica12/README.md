# Práctica 12 — Servidor de Correo Privado con Docker

Infraestructura completa de correo electrónico auto-hospedado con webmail incluido. Garantiza soberanía total de los datos dentro de la organización.

---

## Arquitectura

```
practica12/
├── docker-compose.yml        # Orquestación de los 5 servicios
├── mailserver.env            # Configuración del servidor de correo
├── .env.example              # Plantilla de secretos (copiar a .env)
├── setup.sh                  # Script de inicialización
│
├── nginx/                    # Proxy inverso HTTPS con SSL self-signed
│   ├── Dockerfile
│   ├── nginx.conf
│   └── entrypoint.sh         # Genera el certificado al primer arranque
│
├── backup/                   # Respaldo automático cada 24h
│   ├── Dockerfile
│   ├── backup.sh
│   └── crontab
│
├── webmail/
│   └── config.inc.php        # Configuración de Roundcube
│
├── config/                   # Generado por docker-mailserver (DKIM, cuentas, SSL)
├── logs/                     # Logs de Postfix/Dovecot en tiempo real
└── backups/                  # Respaldos comprimidos + backup.log
```

### Stack de servicios

| Contenedor | Imagen | Función |
|---|---|---|
| `mailserver` | docker-mailserver | Postfix (SMTP) + Dovecot (IMAP) + Rspamd + Fail2ban + OpenDKIM |
| `roundcube` | roundcube/roundcubemail | Webmail PHP |
| `roundcube_db` | mariadb:10.11 | Base de datos de preferencias de Roundcube |
| `mail_nginx` | nginx:alpine (custom) | Proxy HTTPS con certificado self-signed |
| `mail_backup` | alpine (custom) | Cron de respaldo diario de buzones |

### Puertos expuestos

| Puerto | Protocolo | Uso |
|---|---|---|
| 25 | SMTP | Recepción de correo entrante |
| 587 | SUBMISSION | Envío autenticado (Roundcube → mailserver) |
| 465 | SMTPS | Envío cifrado alternativo |
| 143 | IMAP | Acceso a buzón sin cifrar (interno) |
| 993 | IMAPS | Acceso a buzón cifrado (Roundcube → mailserver) |
| 80 | HTTP | Redirige a HTTPS |
| 443 | HTTPS | Portal Roundcube |

---

## Requisitos previos

- Docker >= 24.0 y Docker Compose plugin
- OpenSUSE Leap: abrir puertos en firewalld

```bash
sudo firewall-cmd --permanent --add-port={25,80,143,443,465,587,993}/tcp
sudo firewall-cmd --reload
```

---

## Despliegue

### 1. Inicialización (una sola vez)

```bash
chmod +x setup.sh
./setup.sh
```

El script crea el `.env`, los directorios necesarios y añade `mail.reprobados.com` a `/etc/hosts`.

### 2. Levantar los servicios

```bash
docker compose up -d --build
```

### 3. Crear las cuentas de usuario

Esperar ~30 segundos a que `mailserver` termine de inicializar:

```bash
docker exec mailserver setup email add director@reprobados.com 'PassSegura1!'
docker exec mailserver setup email add admin@reprobados.com 'PassSegura2!'
```

### 4. Generar claves DKIM

```bash
docker exec mailserver setup config dkim
```

Esto genera el par de claves en `./config/opendkim/keys/reprobados.com/`. El registro DNS TXT que deberías publicar (para entorno real) se puede ver con:

```bash
cat config/opendkim/keys/reprobados.com/mail.txt
```

### 5. Acceder al webmail

Abrir en el navegador:

```
https://mail.reprobados.com
```

Aceptar la advertencia del certificado self-signed. Iniciar sesión con `director@reprobados.com` y su contraseña.

---

## Configuración DNS local (dominio simulado)

Como `reprobados.com` es un dominio local, el archivo `/etc/hosts` simula los registros DNS:

| Registro | Valor | Propósito |
|---|---|---|
| A | `127.0.0.1 mail.reprobados.com` | Resuelve el servidor de correo |
| (simulado) MX | `mail.reprobados.com` | Intercambio de correo |
| (simulado) SPF | `v=spf1 ip4:127.0.0.1 -all` | Autorización de envío |
| (simulado) DKIM | Ver `config/opendkim/keys/` | Firma digital |

En un entorno real con dominio público, estos registros se configurarían en el panel DNS del proveedor de dominio.

---

## Protocolo de pruebas

### Prueba 12.1 — Envío y recepción local

**Acción:** enviar un correo de `director@` a `admin@` desde Roundcube.

```
1. Acceder a https://mail.reprobados.com
2. Iniciar sesión como director@reprobados.com
3. Redactar → Para: admin@reprobados.com → Enviar
4. Cerrar sesión
5. Iniciar sesión como admin@reprobados.com
6. Verificar que el correo está en la bandeja de entrada
```

**Resultado esperado:** el correo aparece en la bandeja de entrada de admin sin errores de cifrado.

---

### Prueba 12.2 — Auditoría de registros (logging)

**Acción:** consultar el log de correo después de un envío.

```bash
# En tiempo real
docker exec mailserver tail -f /var/log/mail/mail.log

# O desde el volumen bind-mount del host
tail -f logs/mail.log
```

**Resultado esperado:** el log muestra el flujo completo:

```
postfix/submission/smtpd: connect from roundcube[...]
postfix/submission/smtpd: ... sasl_method=PLAIN, sasl_username=director@reprobados.com
postfix/local: ... to=<admin@reprobados.com>, status=sent
dovecot: imap-login: Login: user=<admin@reprobados.com>, ...
```

---

### Prueba 12.3 — Verificación de seguridad Fail2ban

**Acción:** intentar 5 autenticaciones fallidas por IMAP.

```bash
# Desde la terminal, intentar login incorrecto 5 veces
for i in $(seq 1 6); do
    curl -s --max-time 5 imaps://mail.reprobados.com \
         --user "director@reprobados.com:contraseniaMAL" \
         --insecure || true
    sleep 2
done
```

**Verificar el bloqueo:**

```bash
docker exec mailserver fail2ban-client status dovecot
```

**Resultado esperado:** la IP aparece en la lista de IPs baneadas (`Banned IP list`).

---

### Prueba 12.4 — Integridad de respaldo

**Acción:** borrar un correo, restaurar el respaldo y verificar la reaparición.

```bash
# 1. Forzar un respaldo manual inmediato
docker exec mail_backup /usr/local/bin/backup.sh

# 2. Verificar que se generó
ls -lh backups/

# 3. Borrar un correo desde Roundcube (vaciar papelera también)

# 4. Detener el contenedor de mailserver
docker compose stop mailserver

# 5. Restaurar el último respaldo en el volumen mail_data
ULTIMO=$(ls backups/mail_*.tar.gz | tail -1)
docker run --rm \
    -v practica12_mail_data:/var/mail \
    -v "$(pwd)/backups:/backups" \
    alpine:3.19 \
    sh -c "cd / && tar -xzf /backups/$(basename $ULTIMO)"

# 6. Reiniciar mailserver
docker compose start mailserver

# 7. Verificar en Roundcube que el correo volvió
```

**Resultado esperado:** el correo borrado reaparece en la bandeja con sus metadatos intactos.

---

### Prueba 12.5 — Inicio de sesión institucional (webmail)

**Acción:** acceder al portal desde el navegador.

```
URL: https://mail.reprobados.com
Usuario: director@reprobados.com  (solo escribir "director" — el dominio se completa automáticamente)
```

**Resultado esperado:** la bandeja de entrada carga correctamente mostrando los correos existentes. El título de la página muestra "Reprobados Mail".

---

### Prueba 12.6 — Envío de adjuntos y seguridad

**Acción:** desde Roundcube, redactar un correo con archivo adjunto.

```
1. Redactar → adjuntar cualquier archivo (PDF, imagen, etc.)
2. Enviar a admin@reprobados.com
3. Iniciar sesión como admin@ y descargar el adjunto
4. Verificar integridad: comparar tamaño/hash con el original
```

```bash
# Verificar hash del archivo original vs descargado
md5sum archivo_original.pdf
md5sum archivo_descargado.pdf
```

**Resultado esperado:** ambos hashes son idénticos.

---

### Prueba 12.7 — Persistencia de preferencias

**Acción:** cambiar idioma o agregar un contacto, luego reiniciar el contenedor de webmail.

```bash
# 1. En Roundcube: Configuración → Preferencias → Idioma de interfaz → cambiar
#    O: Contactos → Nuevo contacto → guardar

# 2. Reiniciar el contenedor de Roundcube
docker compose restart roundcube

# 3. Volver a iniciar sesión
# 4. Verificar que el cambio persiste
```

**Resultado esperado:** los cambios de configuración sobreviven al reinicio gracias al volumen `roundcube_db_data`.

---

## Comandos de administración

```bash
# Ver estado de todos los servicios
docker compose ps

# Ver logs en tiempo real
docker compose logs -f mailserver
docker compose logs -f mail_nginx

# Listar cuentas de correo
docker exec mailserver setup email list

# Cambiar contraseña de una cuenta
docker exec mailserver setup email update director@reprobados.com 'NuevaPass!'

# Ver IPs baneadas por Fail2ban
docker exec mailserver fail2ban-client status

# Forzar respaldo inmediato
docker exec mail_backup /usr/local/bin/backup.sh

# Ver historial de respaldos
cat backups/backup.log

# Detener todo (conserva volúmenes y datos)
docker compose down

# Detener todo Y borrar volúmenes (¡pierde todos los correos!)
docker compose down -v
```

---

## Descripción del cifrado (sección para el informe)

El cifrado opera en dos capas:

**1. Usuario → Servidor (HTTPS)**
El navegador se conecta al contenedor `mail_nginx` por TLS 1.2/1.3. El certificado self-signed cifra la contraseña y el contenido desde que el usuario pulsa "Iniciar sesión". Nginx termina el TLS y reenvía la petición a Roundcube por HTTP interno dentro de la red `mail_net` de Docker.

**2. Roundcube → Servidor de correo (IMAPS/STARTTLS)**
Roundcube se autentica contra Dovecot en el puerto 993 (IMAPS, TLS completo) para leer el buzón. Para envío usa el puerto 587 con STARTTLS. Ambas conexiones usan el certificado self-signed del `mailserver`, con verificación de par deshabilitada para aceptar el certificado propio.

**DKIM + SPF**
Postfix firma cada correo saliente con la clave privada DKIM almacenada en `./config/opendkim/keys/`. El receptor verifica la firma con la clave pública publicada en DNS. SPF autoriza a la IP del servidor como remitente legítimo del dominio, previniendo spoofing.

---

## Decisiones de diseño

1. **ClamAV deshabilitado:** consume ~700 MB de RAM por sí solo. Para la práctica en una VM de 4 GB es prescindible; Rspamd ya filtra spam.
2. **Nginx como proxy SSL:** Roundcube no maneja HTTPS nativamente en su imagen Docker. Separar el TLS en nginx es el patrón estándar y facilita reemplazar el certificado sin reconstruir la imagen.
3. **Bind mount para config/ y logs/:** permite inspeccionar claves DKIM y logs directamente desde el host sin `docker exec`.
4. **Volumen nombrado mail_data:** los buzones viven en un volumen gestionado por Docker, independiente del ciclo de vida del contenedor, lo que simplifica la restauración.
5. **Backup en contenedor separado:** principio de mínimo privilegio — accede al volumen de correo en modo solo lectura.
