# Variables

`ansible/inventories/on-premise/group_vars/all/vars.yml` — variables **non
sensibles** du groupe `all`. Les secrets sont dans `vault.yml` (chiffré) et
rattachés en bas de `vars.yml` par indirection `{{ vault_* }}` — voir
[Secrets](../secrets/index.md).

Les rôles portent chacun leurs propres défauts dans `defaults/main.yml` ;
`vars.yml` ne surcharge que ce qui change pour cet environnement.

## Traefik

| Variable | Valeur | Rôle |
|---|---|---|
| `traefik_domain` | `traefik.enervision.com` | domaine du tableau de bord |
| `traefik_entrypoint` | `web` | entrypoint des routeurs applicatifs (`web` = :80 HTTP) |
| `traefik_certresolver` | `letsencrypt` | résolveur ACME (non attaché aujourd'hui) |
| `acme_email` | `admin@enervision.com` | contact Let's Encrypt |

## Garage

| Variable | Valeur |
|---|---|
| `garage_s3_host` | `s3.enervision.com` |
| `garage_web_host` | `web.enervision.com` |
| `garage_ui_host` | `garage.enervision.com` |
| `garage_s3_region` | `garage` |
| `garage_s3_root_domain` | `.s3.enervision.com` |
| `garage_web_root_domain` | `.web.enervision.com` |
| `garage_layout_zone` *(défaut rôle)* | `dc1` |
| `garage_layout_capacity` *(défaut rôle)* | `64G` |

## PostgreSQL

| Variable | Valeur |
|---|---|
| `postgres_db` | `enervision` |
| `postgres_user` | `enervision` |
| `postgres_image` *(défaut rôle)* | `postgres:17.10-alpine3.24` |
| `postgres_bind_address` *(défaut rôle)* | `127.0.0.1` |
| `postgres_port` *(défaut rôle)* | `5432` |
| `postgres_pgweb_enabled` *(défaut rôle)* | `true` (console temporaire, `127.0.0.1:8081`) |

## Kafka

| Variable | Valeur |
|---|---|
| `kafka_image` *(défaut rôle)* | `apache/kafka:3.9.2` |
| `kafka_ui_image` *(défaut rôle)* | `ghcr.io/kafbat/kafka-ui:v1.5.0` |
| `kafka_cluster_id` *(défaut rôle)* | `enervision-kraft-cluster1` |
| `kafka_publish_broker` *(défaut rôle)* | `false` |
| `kafka_ui_enabled` *(défaut rôle)* | `true` (console temporaire, `127.0.0.1:8080`) |
| `kafka_topics` *(défaut rôle)* | `energy.data.raw`, `energy.data.enriched` (1 partition, réplication 1) |

## MLflow

| Variable | Valeur |
|---|---|
| `mlflow_base_image` *(défaut rôle)* | `ghcr.io/mlflow/mlflow:v3.1.1` (FROM du Dockerfile généré) |
| `mlflow_backend_store_uri` *(défaut rôle)* | `sqlite:////mlflow/mlflow.db` |
| `mlflow_artifacts_destination` *(défaut rôle)* | `/mlflow/artifacts` (volume local ; `wasbs://…` pour Azure Blob) |
| `mlflow_azure_connection_string` | `vault_mlflow_azure_connection_string` (requis si destination `wasbs://`) |

## Monitoring

| Variable | Valeur |
|---|---|
| `monitoring_grafana_host` | `grafana.enervision.com` |
| `monitoring_grafana_admin_user` | `admin` |
| `monitoring_prometheus_retention` *(défaut rôle)* | `15d` |

## Applications — hôtes et réglages

| Variable | Valeur |
|---|---|
| `applications_front_host` | `app.enervision.com` |
| `applications_api_host` | `api.enervision.com` |
| `applications_api_environment` | `production` |
| `applications_api_auth_enabled` | `true` |
| `applications_api_jwt_algorithm` | `HS256` |
| `applications_api_access_token_expire_minutes` | `60` |
| `applications_collector_networks` *(défaut rôle)* | `[broker_network]` |

## Applications — versions déployées

| Variable | Image | Tag |
|---|---|---|
| `applications_front_sha` | `ghcr.io/enervision-g5/dashboard` | `sha-…` |
| `applications_api_sha` | `ghcr.io/enervision-g5/api` | `sha-…` |
| `applications_collector_sha` | `ghcr.io/enervision-g5/collector` | `sha-…` |

MLflow n'est plus une application : il est déployé par le rôle `mlflow`
(`provision.yml`), avec sa propre image construite sur place. Voir
[Services › MLflow](../services/mlflow.md). `serving`, `training`, `etl` et
`predict-cron` ont été retirés (chaîne ML en reconstruction autour de Kafka).

## `applications_enabled`

```yaml
applications_enabled:
  - front
  - api
  # - collector   # dès que applications_collector_sha est renseigné
```

## Réseaux

```yaml
docker_external_networks:
  - proxy_network
  - api_network
  - db_network
  - storage_network
  - ml_network
  - monitoring_network
  - broker_network
```

## Rattachement des secrets (indirection Vault)

| Variable métier | Clé Vault | Consommée par |
|---|---|---|
| `garage_rpc_secret` | `vault_garage_rpc_secret` | garage |
| `garage_admin_token` | `vault_garage_admin_token` | garage, garage-webui |
| `garage_metrics_token` | `vault_garage_metrics_token` | garage |
| `postgres_password` | `vault_postgres_password` | postgres, applications |
| `ghcr_username` | `vault_ghcr_username` | applications (login GHCR) |
| `ghcr_token` | `vault_ghcr_token` | applications (login GHCR) |
| `monitoring_grafana_admin_password` | `vault_monitoring_grafana_admin_password` | monitoring |
| `applications_api_jwt_secret` | `vault_applications_api_secret_key` | api (`JWT_SECRET`) |
| `mlflow_azure_connection_string` | `vault_mlflow_azure_connection_string` | mlflow (si artefacts `wasbs://`) |
| `ansible_password` | `vault_ansible_ssh_password` | connexion SSH (`hosts.yml`) |
