# Réseaux & ports

## Réseaux Docker → services

| Réseau | Services attachés |
|---|---|
| `proxy_network` | traefik, front, api, serving, grafana, garage, garage-webui, mlflow *(si exposé)* |
| `db_network` | timescaledb, api, collector, etl, predict-cron, training |
| `ml_network` | api, serving, mlflow, training, predict-cron |
| `storage_network` | garage, serving, etl, training, mlflow *(si artefacts `s3://`)* |
| `monitoring_network` | prometheus, grafana, loki, promtail, node-exporter, cadvisor, traefik |
| `api_network` | *(créé, non utilisé)* |

## Ports publiés sur l'hôte

| Bind | Port | Service | Usage |
|---|---|---|---|
| `0.0.0.0` | 80 | traefik (`web`) | trafic HTTP public |
| `0.0.0.0` | 443 | traefik (`websecure`) | HTTPS (tableau de bord seulement aujourd'hui) |
| `127.0.0.1` | 5432 | timescaledb | administration `psql` |
| `127.0.0.1` | 5000 | mlflow | tunnel SSH vers l'interface |

Tout le reste est **interne aux réseaux Docker** — pas de port publié.

## Ports internes (cibles Traefik `loadbalancer.server.port`)

| Service | Port interne |
|---|---|
| front | 8080 |
| api | 8080 |
| serving | 8000 |
| grafana | 3000 |
| mlflow | 5000 |
| garage — S3 | 3900 |
| garage — web | 3902 |
| garage — admin API | 3903 |
| garage — RPC | 3901 |
| garage-webui | 3909 |

## Ports internes monitoring (scrape Prometheus)

| Cible | Port | Job Prometheus |
|---|---|---|
| `localhost:9090` | 9090 | `prometheus` |
| `node-exporter:9100` | 9100 | `node-exporter` |
| `cadvisor:8080` | 8080 | `cadvisor` |
| `traefik:8082` | 8082 | `traefik` (entrypoint `metrics`) |
| `loki:3100` | 3100 | *(datasource Grafana, pas scrapé)* |
| `promtail:9080` | 9080 | *(non scrapé)* |
