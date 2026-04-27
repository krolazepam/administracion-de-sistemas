# Scripts de las 4 pruebas de validación

Cada script corre una prueba completa con sus pasos numerados y separadores en color, para que las capturas queden ordenadas y legibles.

## Estructura

```
pruebas/
├── lib-mensajes.sh       ← funciones reutilizables (titulo, paso, nota, fin)
├── prueba1.sh            ← Persistencia BD
├── prueba2.sh            ← Aislamiento de red
├── prueba3.sh            ← Permisos FTP
├── prueba4.sh            ← Límites de recursos
└── ejecutar-todas.sh     ← corre las 4 en orden
```

Los scripts de prueba **dependen de `lib-mensajes.sh`**, que centraliza colores y formato. Si quieres cambiar la paleta o los estilos, lo haces en un solo lugar.

## Cómo usarlos

Dentro de la carpeta `practica-docker/`, crea una subcarpeta `pruebas/` y coloca todos los scripts ahí:

```bash
cd ~/practica-docker
mkdir -p pruebas
# (mueve los .sh aquí)
cd pruebas
chmod +x *.sh

sh prueba1.sh    # o cualquiera de las otras
```

O ejecuta todas en secuencia:

```bash
sh ejecutar-todas.sh
```

## Qué demuestra cada prueba

| Prueba | Qué demuestra |
|---|---|
| 10.1 | El volumen `db_data` conserva los datos al destruir el contenedor |
| 10.2 | Resolución por nombre dentro de `infra_red` |
| 10.3 | El volumen `web_content` es compartido entre FTP y WEB |
| 10.4 | Límites de RAM y CPU configurados a nivel kernel |

## Sobre la librería `lib-mensajes.sh`

Expone 5 funciones:

| Función | Uso |
|---|---|
| `titulo "texto"` | Encabezado de la prueba (cyan) |
| `paso N "descripción"` | Paso numerado (gris) |
| `nota "texto"` | Aclaración secundaria (gris) |
| `fin "nombre" "mensaje"` | Cierre con resumen (verde) |
| `espaciado` | Salto de línea limpio |

Si quieres cambiar el color del título, por ejemplo de cyan a azul, edita la constante `COLOR_TITULO` en `lib-mensajes.sh` y los 4 scripts cambian al instante.

## Tip para tu reporte

Si quieres guardar la salida en un archivo de texto en lugar de capturar pantalla:

```bash
sh prueba1.sh > evidencia-10.1.txt 2>&1
cat evidencia-10.1.txt
```

## Detalle importante

El `prueba1.sh` necesita acceder al `docker-compose.yml` que está en la carpeta padre (`practica-docker/`). Lo hace con un subshell `( cd .. && ... )` para no afectar el directorio actual del script. Por eso es necesario que los scripts vivan dentro de `practica-docker/pruebas/`.
