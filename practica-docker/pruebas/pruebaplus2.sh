# Mostrar quienes estan en la red (dockers)
docker network inspect infra_red --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}'