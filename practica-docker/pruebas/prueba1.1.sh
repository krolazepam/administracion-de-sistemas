# Cambiar el usuario y la BD
# Crear un usuario para probar la BD
docker exec -it infra_db psql -U midori -d practica10 -c "INSERT INTO usuarios (nombre, email, password) VALUES ('Pruebita AS', 'pruebita@test.com', 'hash');"

# Seleccionar los usuarios quee existen en esa DB
docker exec -it infra_db psql -U midori -d practica10 -c "SELECT id, nombre, email FROM usuarios;"

