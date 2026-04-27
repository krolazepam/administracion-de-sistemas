# Comprobar la subred personalizada
docker network inspect infra_red | grep -E "Subnet|Gateway"