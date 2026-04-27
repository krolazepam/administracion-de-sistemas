# Cambiar el usuario y la BD
# Crear un usuario para probar la BD
docker exec -it infra_db psql -U dualy -d prueba1 -c "INSERT INTO usuarios (nombre, email, password) VALUES ('Prueba Persistencia', 'persist@test.com', 'hash');"

# Seleccionar los usuarios quee existen en esa DB
docker exec -it infra_db psql -U dualy -d prueba1 -c "SELECT id, nombre, email FROM usuarios;"

