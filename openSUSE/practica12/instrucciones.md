# Practica 12
el objetivo es desplegar una solución de correo electrónico completa "en casa", garantizando la soberanía de los datos. 

competencias a desarrollar:
orquestación de protocolos: configuración de protocolo simple de transferencia de correo (smtp) para envío y protocolo de acceso a mensajes de internet (imap) para recepción.
seguridad criptográfica: implementación de certificados para cifrado de extremo a extremo.
gestión de registros y auditoría: configuración de trazabilidad completa para cada mensaje que entra o sale.
resiliencia y respaldos: diseño de una estrategia de recuperación ante desastres para los buzones de correo.
Arquitectura del servicio (el stack técnico)

Utilizarán docker compose para levantar una infraestructura basada en el proyecto mailserver, que integra los siguientes componentes:
postfix: el agente de transferencia de correo (mail transfer agent - mta) encargado del protocolo smtp.
dovecot: el agente de entrega de correo (mail delivery agent - mda) que gestiona los buzones y el protocolo imap.
rspamd: sistema de filtrado de correo no deseado (spam) y antivirus integrado.
fail2ban: herramienta de prevención de intrusiones que bloquea direcciones ip tras múltiples intentos fallidos de conexión.
opendkim: implementación de correo identificado con claves de dominio (domainkeys identified mail - dkim) para firmar digitalmente los correos salientes.
Detaalle de las actividades a desarrollar;

1. configuración de identidad y dns
registros mx: configurar el servidor de nombres de dominio (domain name system - dns) para que el registro de intercambio de correo (mail exchanger - mx) apunte a la dirección ip del contenedor.

registros spf y dkim: configurar el marco de políticas del remitente (sender policy framework - spf) para autorizar al servidor a enviar correos, evitando que sean marcados como fraudulentos por otros servidores.

2. seguridad y cifrado
tls/ssl: generar certificados para asegurar que toda comunicación viaje cifrada. se debe forzar el uso de tls (transport layer security).

monitoreo y logging: configurar el envío de registros (logs) a un volumen persistente para que el administrador de auditoría pueda revisar quién envió correos y desde qué ubicación geográfica.

3. almacenamiento y respaldo
volúmenes de buzones: los correos deben almacenarse en un volumen nombrado (mail_data).

script de respaldo: crear una tarea programada que realice una copia de seguridad comprimida de los buzones (/var/mail) cada 24 horas.


pruebas de aceptación
el estudiante debe demostrar que su servidor es apto para un entorno corporativo real:

prueba 12.1: envío y recepción local
acción: crear dos cuentas de usuario (ej. director@reprobados.com y admin@reprobados.com) y enviar un correo entre ellas usando un cliente como thunderbird o mailspring.
resultado esperado: el correo llega instantáneamente y se puede leer sin errores de cifrado.
prueba 12.2: auditoría de registros (logging)
acción: realizar un envío y luego consultar los archivos de registro en /var/log/mail.log.
resultado esperado: el registro debe mostrar el flujo completo: conexión, autenticación exitosa, transferencia del mensaje y desconexión.

prueba 12.3: verificación de seguridad fail2ban
acción: intentar iniciar sesión con una contraseña incorrecta 5 veces seguidas desde una terminal remota.
resultado esperado: la dirección ip del atacante debe ser bloqueada por el firewall del servidor automáticamente.

prueba 13.4: integridad de respaldo
acción: borrar un correo, detener el contenedor, restaurar el último respaldo y verificar la reaparición del correo.
resultado esperado: recuperación total de la información sin pérdida de metadatos.
¿por qué un servidor de correo privado?
en el entorno empresarial actual, el correo electrónico contiene secretos industriales, estrategias financieras y datos personales sensibles. el uso de proveedores externos (nube) implica ceder la custodia de estos datos a terceros. un servidor privado bajo un modelo de nube privada garantiza que los datos nunca salgan de la infraestructura física de la organización.

el rol de dkim y spf en la confianza:
el protocolo spf es una lista blanca de servidores autorizados, mientras que dkim añade una firma criptográfica al encabezado del mensaje. juntos, estos mecanismos previenen el "spoofing" (suplantación de identidad), asegurando que el receptor pueda confiar en que el correo realmente proviene de la organización.

esta práctica consolida todos los conocimientos de redes, seguridad, linux y docker adquiridos durante el curso, entregando una solución lista para implementarse.


PARTE DOS
introducción 
el objetivo es desplegar una interfaz de usuario profesional que se comunique con el servidor de correo configurado previamente. se busca replicar la experiencia de servicios como gmail o outlook, pero bajo control total de la organización.

competencias a desarrollar:
integración de aplicaciones multicapa: conectar un frontend web con servicios de backend mediante protocolos estándar (imap/smtp).
seguridad en aplicaciones web: implementar cifrado de capa de sockets seguros (secure sockets layer - ssl) para proteger las credenciales del usuario en el navegador.
optimización de experiencia de usuario: configurar una interfaz fluida y segura que resida en un contenedor independiente.
arquitectura del portal web (complemento al stack)
añadiremos a nuestra orquestación de docker compose el siguiente servicio:
roundcube webmail: un cliente de correo basado en web escrito en php, altamente seguro y personalizable.
base de datos del portal (mariadb/sqlite): necesaria para que el portal webmail almacene las preferencias de los usuarios, libretas de direcciones y configuraciones personales.
técnicas de integración

1. orquestación del contenedor webmail: configurar el contenedor de roundcube para que se conecte automáticamente al servidor de correo privado configurado anteriormente.
configuración crítica: el portal web debe utilizar el puerto 80 o 443 del host. se debe asegurar que la comunicación interna entre el webmail y el servidor de correo ocurra a través de la red privada de docker.
2. seguridad del portal: forzado de https: configurar el servidor web para que no permita conexiones sin cifrado.
protección de sesión: ajustar el tiempo de expiración de las sesiones para que, tras un periodo de inactividad, el usuario sea desconectado automáticamente.
3. personalización institucional: modificar el archivo de configuración para incluir el logotipo de la organización y el nombre del dominio (reprobados.com) como dominio predeterminado para el inicio de sesión.

pruebas de aceptación (guía de interfaz)
el estudiante debe validar el acceso universal a través del portal:

prueba 13.5: inicio de sesión institucional
acción: acceder a la url del servidor desde un navegador e iniciar sesión con las credenciales creadas en la sección anterior.
resultado esperado: el portal carga la bandeja de entrada correctamente y muestra los correos existentes.
prueba 13.6: envío de adjuntos y seguridad
acción: redactar un correo desde el portal web con un archivo adjunto y enviarlo a otra cuenta local.
resultado esperado: el correo se envía exitosamente y el archivo adjunto mantiene su integridad (verificable al descargarlo).
prueba 13.7: persistencia de preferencias
acción: cambiar el idioma de la interfaz o añadir un contacto a la libreta de direcciones, reiniciar el contenedor de webmail y volver a entrar.
resultado esperado: los cambios deben persistir gracias al volumen de la base de datos del portal.
la importancia de los clientes webmail en la nube privada:
un portal webmail actúa como un intermediario (proxy) entre el usuario final y los protocolos de correo. su principal ventaja en una organización es la prevención de fuga de datos (data loss prevention - dlp), ya que los correos no se descargan necesariamente a las computadoras locales de los empleados, sino que permanecen en el servidor centralizado, facilitando la auditoría y el control.

protocolos de comunicación interna:
mientras que el usuario ve una página web, el servidor webmail utiliza el protocolo de acceso a mensajes de internet (imap) para "leer" el buzón y el protocolo simple de transferencia de correo (smtp) para realizar envíos. esta separación de funciones permite que el servidor web sea ligero y escalable.

Añadir al infome de la práctica

sección de orquestación: el archivo docker-compose.yml actualizado con los servicios de correo y el servicio de webmail.
sección de seguridad: descripción de cómo se configuró el cifrado para proteger la contraseña del usuario desde que se escribe en el navegador hasta que llega al servidor.
matriz de pruebas extendida: incluir las pruebas de envío desde el cliente de escritorio (thunderbird) y desde el portal web (roundcube).