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

## TimescaleDB

| Variable | Valeur |
|---|---|
| `timescaledb_db` | `enervision` |
| `timescaledb_user` | `enervision` |
| `timescaledb_image` *(défaut rôle)* | `timescale/timescaledb:2.17.2-pg16` |
| `timescaledb_bind_address` *(défaut rôle)* | `127.0.0.1` |
| `timescaledb_port` *(défaut rôle)* | `5432` |

## Monitoring

| Variable | Valeur |
|---|---|
| `monitoring_grafana_host` | `grafana.enervision.com` |
| `monitoring_grafana_admin_user` | `admin` |
| `monitoring_prometheus_retention` *(défaut rôle)* | `15d` |

## Backup

| Variable | Valeur |
|---|---|
| `backup_azure_account_name` | `stenervisiontfca5c57` |
| `backup_azure_container` | `prod-backups` |
| `backup_azure_client_id` | `api-rw.client_id` (identité fédérée PROD) |
| `backup_azure_tenant_id` | locataire Azure |
| `backup_workload_subject` | `prod/api-rw` |
| `backup_workload_kid` | `prod-20260908` |
| `backup_restic_image` *(défaut rôle)* | `restic/restic:0.19.1` |
| `backup_keep_daily / weekly / monthly / yearly` *(défaut rôle)* | `7 / 1 / 3 / 1` |
| `backup_dump_on_calendar` *(défaut rôle)* | `*-*-* 02:00:00` |
| `backup_on_calendar` *(défaut rôle)* | `*-*-* 04:00:00` |
| `backup_check_on_calendar` *(défaut rôle)* | `Sun *-*-* 05:00:00` |

## Applications — hôtes et réglages

| Variable | Valeur |
|---|---|
| `applications_front_host` | `app.enervision.com` |
| `applications_api_host` | `api.enervision.com` |
| `applications_serving_host` | `predict.enervision.com` |
| `applications_mlflow_expose` | `true` |
| `applications_mlflow_host` | `mlflow.enervision.com` |
| `applications_api_environment` | `production` |
| `applications_api_auth_enabled` | `true` |
| `applications_api_jwt_algorithm` | `HS256` |
| `applications_api_access_token_expire_minutes` | `60` |
| `applications_predict_storage_root` | `s3://enervision-features` |
| `applications_predict_s3_endpoint_url` | `http://garage:3900` |
| `applications_serving_model_uri` | `models:/enervision_xgboost@champion` |
| `applications_training_experiment` | `enervision-consumption` |
| `applications_training_history_days` | `90` |
| `applications_training_promote` | `false` |
| `applications_training_on_calendar` | `Sun *-*-* 03:30:00` |
| `applications_collector_env` | `production` |
| `applications_collector_mock_api_url` | `http://10.105.200.45:8000` *(à vérifier)* |
| `applications_collector_backfill_on_calendar` | `*-*-* 02:30:00` |
| `applications_collector_backfill_days` | `2` |

## Applications — versions déployées

| Variable | Image | Tag |
|---|---|---|
| `applications_front_sha` | `ghcr.io/enervision-g5/dashboard` | `sha-dadeb47…` |
| `applications_api_sha` | `ghcr.io/enervision-g5/api` | `sha-665d1e5…` |
| `applications_serving_sha` | `ghcr.io/enervision-g5/predict/serving` | `sha-48709c6…` |
| `applications_training_sha` | `ghcr.io/enervision-g5/predict/training` | `sha-da9407f…` |
| `applications_etl_sha` | `ghcr.io/enervision-g5/predict/etl` | `sha-da9407f…` |
| `applications_collector_sha` | `ghcr.io/enervision-g5/predict/collector` | `sha-48709c6…` |

`mlflow` réutilise l'image `training` ; `predict-cron` réutilise l'image
`api`. Voir [Services › Applications](../services/applications/index.md).

## `applications_enabled`

```yaml
applications_enabled:
  - front
  - api
  - mlflow
  - serving
  - training
  - collector
  - etl
  - predict-cron
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
```

## Rattachement des secrets (indirection Vault)

| Variable métier | Clé Vault | Consommée par |
|---|---|---|
| `garage_rpc_secret` | `vault_garage_rpc_secret` | garage |
| `garage_admin_token` | `vault_garage_admin_token` | garage, garage-webui |
| `garage_metrics_token` | `vault_garage_metrics_token` | garage |
| `timescaledb_password` | `vault_timescaledb_password` | timescaledb, applications |
| `ghcr_username` | `vault_ghcr_username` | applications (login GHCR) |
| `ghcr_token` | `vault_ghcr_token` | applications (login GHCR) |
| `monitoring_grafana_admin_password` | `vault_monitoring_grafana_admin_password` | monitoring |
| `applications_api_jwt_secret` | `vault_applications_api_secret_key` | api (`JWT_SECRET`) |
| `applications_predict_s3_access_key_id` | `vault_garage_s3_access_key_id` | serving, training, etl |
| `applications_predict_s3_secret_access_key` | `vault_garage_s3_secret_access_key` | serving, training, etl |
| `applications_mlflow_basic_auth_users` | `vault_applications_mlflow_basic_auth_users` | mlflow (si exposé) |
| `ansible_password` | `vault_ansible_ssh_password` | connexion SSH (`hosts.yml`) |
| `backup_restic_password` | `vault_backup_restic_password` | backup (chiffrement du dépôt restic) |
| `backup_workload_issuer_key` | `vault_workload_issuer_key` | backup (clé privée de l'émetteur) |
