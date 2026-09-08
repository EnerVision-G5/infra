# Versions d'images

Tout est épinglé. Deux niveaux : les images **socle** (dans les
`defaults/main.yml` des rôles) et les images **applicatives** (dans
`vars.yml`, par SHA de commit).

## Images socle — rôles `provision.yml`

| Image | Version | Rôle · variable |
|---|---|---|
| `traefik` | `v3.7.9` | `traefik` *(en dur dans le template)* |
| `dxflrs/garage` | `v2.0.0` | `garage` *(en dur)* |
| `khairul169/garage-webui` | `1.1.0` | `garage` *(en dur)* |
| `postgres` | `17.10-alpine3.24` | `postgres` · `postgres_image` |
| `sosedoff/pgweb` | `0.16.2` | `postgres` · `postgres_pgweb_image` |
| `apache/kafka` | `3.9.2` | `kafka` · `kafka_image` |
| `ghcr.io/kafbat/kafka-ui` | `v1.5.0` | `kafka` · `kafka_ui_image` |
| `ghcr.io/mlflow/mlflow` | `v3.1.1` | `mlflow` · `mlflow_base_image` *(FROM du Dockerfile généré + `azure-storage-blob`)* |
| `grafana/grafana` | `11.4.0` | `monitoring` · `monitoring_grafana_image` |
| `prom/prometheus` | `v3.1.0` | `monitoring` · `monitoring_prometheus_image` |
| `grafana/loki` | `3.3.2` | `monitoring` · `monitoring_loki_image` |
| `grafana/promtail` | `3.3.2` | `monitoring` · `monitoring_promtail_image` |
| `prom/node-exporter` | `v1.8.2` | `monitoring` · `monitoring_node_exporter_image` |
| `gcr.io/cadvisor/cadvisor` | `v0.52.1` | `monitoring` · `monitoring_cadvisor_image` |

!!! note "cAdvisor"
    `v0.52.1` est un minimum : les versions antérieures parlent une API
    Docker trop ancienne pour le démon de la VM et n'affichent aucune
    métadonnée conteneur. Voir [Services › Monitoring](../services/monitoring.md).

## Images applicatives — `vars.yml`

Tag GHCR immuable `sha-<git-sha>`, produit par `docker/metadata-action`
dans le pipeline du dépôt qui publie l'image. On ne déploie **jamais**
`latest`.

| Service | Image GHCR | Variable | Dépôt source |
|---|---|---|---|
| front | `enervision-g5/dashboard` | `applications_front_sha` | `dashboard` |
| api | `enervision-g5/api` | `applications_api_sha` | `api` |
| collector | `enervision-g5/collector` | `applications_collector_sha` | `collector` |

Chaque dépôt a un workflow `cd.yml` qui publie une image sous `sha-<git-sha>`.
Le rôle contrôle l'unicité du couple `image:tag`.

MLflow n'est plus une image applicative : le rôle `mlflow` construit son image
sur place (voir « Images socle » ci-dessus). `serving`, `training`, `etl` et
`predict-cron` ont été retirés — chaîne ML en reconstruction autour de Kafka.

## Changer une version

- **Image applicative** → éditer `applications_<service>_sha` dans `vars.yml`,
  puis rejouer `deploy.yml`. Le rôle détecte le changement (fichier `.sha`),
  tire la nouvelle image et redéploie ce seul service.
- **Image socle** → éditer la variable du rôle (ou le template), rejouer
  `provision.yml --tags <role>`.

Détail : [Déploiement › deploy.yml](../deploiement/applications.md).
