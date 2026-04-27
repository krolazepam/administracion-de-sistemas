# Levanta nuevamente el docker y espera unos segundos
docker compose up -d db
sleep 4

# Comprueba que los datos del anterior docker sigan existiendo
# Cambiar el ususario y la BD   
docker exec -it infra_db psql -U dualy -d prueba1 -c "SELECT id, nombre, email FROM usuarios;"