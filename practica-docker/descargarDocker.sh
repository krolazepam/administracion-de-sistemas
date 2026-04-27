# Comprobar si docker esta instalado
docker --version

# Instalar docker
sudo zypper refresh
sudo zypper install -y docker docker-compose unzip curl
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker

# Prueba para comprobar si el docker funciona
docker run --rm hello-world

# Comprobaciones de grupo del docker
getent group docker

# Abrir puertos
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=21/tcp
sudo firewall-cmd --permanent --add-port=30000-30009/tcp
sudo firewall-cmd --reload

# Inicializar la practica
docker-compose up -d --build

# Prueba de funcionamiento
docker compose ps