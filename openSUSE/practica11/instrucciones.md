# Practica 11
El objetivo de esta actividad es dominar la orquestación de infraestructuras complejas utilizando un enfoque de infraestructura como código (infrastructure as code - iac). En un entorno profesional, los servicios no se despliegan de forma aislada.
Que habilidades se desarrollarán:
abstracción de servicios: entender cómo separar la capa de datos, la capa de lógica y la capa de gestión.
seguridad perimetral en contenedores: aprender a ocultar servicios críticos de la red pública.
automatización de dependencias: asegurar que los servicios arranquen en el orden correcto y que la infraestructura sea resiliente ante fallos.
túneles de gestión profesional: utilizar protocolos cifrados para administrar recursos internos sin exponer vectores de ataque.
Deberá diseñar un ecosistema coordinado mediante un archivo de orquestación (docker-compose.yml) que contenga los siguientes servicios integrados:

balanceador de carga y frontend (nginx): actuará como el único punto de entrada público. debe estar configurado para distribuir tráfico y ocultar las cabeceras de versión del servidor.
servidor de aplicaciones (servicio web secundario): un segundo contenedor web que simula una aplicación interna. este contenedor no tendrá puertos expuestos al host; solo será accesible a través del balanceador nginx.
clúster de base de datos (postgresql con persistencia): sistema de gestión de base de datos principal. debe tener volúmenes nombrados para asegurar que la información sea permanente.
panel de control administrativo (pgadmin): herramienta gráfica para gestionar la base de datos. por seguridad, este servicio estará bloqueado para cualquier IP externa.
mejora de gestión (ssh): el sistema anfitrión linux servirá como puerta de enlace cifrada para realizar túneles hacia los servicios internos.
tareas técnicas importantes:
Gestión de información sensible y variabes entorno: todas las credenciales de la base de datos, nombres de usuario y puertos deben gestionarse a través de un archivo de variables de entorno (.env). se penalizará el uso de contraseñas escritas directamente (hardcoded) en los archivos de orquestación.
redes multicapa: definir al menos dos redes internas en docker:
----red_publica: donde reside el balanceador nginx.
----red_datos: donde residen la base de datos y el panel administrativo, totalmente aislada del exterior.
política de reinicio: configurar los contenedores para que se reinicien automáticamente en caso de fallo (restart: always) y establecer dependencias de buen funcionamiento (healthcheck) para que el panel administrativo no inicie hasta que la base de datos esté lista para recibir conexiones.
túnel de administración ssh: configurar el firewall del sistema anfitrión para cerrar el puerto de pgadmin y el de la base de datos. el acceso a estos servicios solo se permitirá mediante un túnel local cifrado (local port forwarding) desde la computadora del estudiante.
protocolo de pruebas de aceptación
el estudiante debe ejecutar las siguientes pruebas para validar que su infraestructura cumple con estándares:

prueba 11.1: validación de aislamiento de red::: acción: desde la máquina física del estudiante, intentar hacer un curl a la dirección ip del servidor en el puerto donde corre la base de datos o el panel administrativo.
:::::::::::::resultado esperado: la conexión debe ser rechazada o dar tiempo de espera (timeout), demostrando que el servicio es invisible fuera de docker.
prueba 11.2: validación de resolución interna dns::::::acción: ejecutar docker exec dentro del contenedor de nginx y realizar un ping al nombre del servicio de la base de datos definido en el archivo de orquestación.
:::::::::::::resultado esperado: éxito en la respuesta, demostrando que los contenedores se encuentran por nombre de servicio y no por direcciones ip fijas.
prueba 11.3: validación de túnel cifrado de gestión:::::::acción: establecer un túnel desde la terminal local: ssh -L 8080:servidor_pgadmin:80 usuario@ip_servidor. abrir localhost:8080 en el navegador local.
:::::::::::::resultado esperado: el panel administrativo debe cargar perfectamente a través del túnel, demostrando la capacidad de gestionar servicios ocultos de forma segura.
prueba 11.4: validación de persistencia y buen funcionamiento::::::acción: detener todo el stack con docker-compose down, borrar los contenedores e iniciar de nuevo.
:::::::::::::resultado esperado: al iniciar, el servicio administrativo debe esperar a que la base de datos esté "healthy" antes de subir, y los datos previos deben estar intactos gracias al volumen.
se debe añadir al reporte:
archivo de orquestación: copia del docker-compose.yml y ejemplo del .env (sin datos reales, si son de prueba no es problema).
diagrama de flujo de datos: dibujo que muestre cómo viaja una petición desde el navegador del estudiante, pasando por el túnel ssh, hasta llegar al contenedor interno. Como opción pueden usar https://mermaid.live/, aunque si usan otra herramienta similar que les de la solicitado, lo pueden usar sin problema.
bitácora de pruebas: capturas de pantalla de las 4 pruebas de validación descritas en el protocolo anterior.
ALGO DE TEORÍA
Infraestructura como Código y Orquestación de Microservicios

Evolución de la Virtualización: Del Hipervisor al Contenedor
Tradicionalmente, la virtualización dependía de máquinas virtuales (Virtual Machines - VM), las cuales emulan un hardware completo y requieren un sistema operativo invitado para cada instancia. Esto genera un alto consumo de recursos. En contraste, la contenedorización permite aislar procesos a nivel de sistema operativo, compartiendo el mismo núcleo (kernel) pero manteniendo entornos de ejecución totalmente independientes.

Infraestructura como Código (Infrastructure as Code - IaC)
El concepto de IaC es la gestión y el aprovisionamiento de infraestructura a través de archivos de definición legibles por máquina, en lugar de configuraciones físicas manuales o herramientas de configuración interactiva.

Docker: Se encarga del empaquetamiento de las aplicaciones y sus dependencias en imágenes.
Docker Compose: Funciona como el orquestador que permite definir y correr aplicaciones multi-contenedor, gestionando redes, volúmenes y dependencias en un solo archivo declarativo.

Seguridad Perimetral y Aislamiento de Redes
En arquitecturas de microservicios, el principio de Defensa en Profundidad dicta que los servicios de backend (como las bases de datos) no deben tener exposición directa a internet.

Redes Bridge (Puente): Docker crea redes virtuales privadas donde los contenedores pueden comunicarse por nombre de servicio mediante un DNS interno, bloqueando el tráfico externo que no pase por los puntos de entrada autorizados (como un balanceador de carga).

Hardening: Consiste en reducir la superficie de ataque eliminando firmas del servidor, limitando privilegios de usuario y cerrando puertos no esenciales.

Gestión de Persistencia y Volúmenes
A diferencia de los archivos en el host, los sistemas de archivos de los contenedores son efímeros (se borran al eliminar el contenedor). Los Volúmenes Nombrados (Named Volumes) de Docker permiten desacoplar los datos del ciclo de vida del contenedor, garantizando que la información de bases de datos como PostgreSQL sea persistente y segura ante reinicios o actualizaciones.

Administración Remota Mediante Túneles SSH
El túnel de Shell Segura (Secure Shell - SSH) es una técnica para transportar datos de red arbitrarios sobre una conexión cifrada. El Reenvío de Puertos Local (Local Port Forwarding) permite que un administrador acceda a un servicio que corre en una red privada del servidor (como el panel administrativo de la base de datos) como si estuviera corriendo en su propia computadora local (localhost), sin necesidad de abrir puertos en el firewall público.