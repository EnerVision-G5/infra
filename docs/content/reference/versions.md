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
| `timescale/timescaledb` | `2.17.2-pg16` | `timescaledb` · `timescaledb_image` |
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
| serving | `enervision-g5/predict/serving` | `applications_serving_sha` | `predict` |
| training | `enervision-g5/predict/training` | `applications_training_sha` | `predict` |
| etl | `enervision-g5/predict/etl` | `applications_etl_sha` | `predict` |
| collector | `enervision-g5/predict/collector` | `applications_collector_sha` | `predict` |
| mlflow | *(= image `training`)* | — | — |
| predict-cron | *(= image `api`)* | — | — |

Le dépôt `predict` publie `serving`, `training`, `etl` et `collector`
**depuis le même commit** : elles portent alors le même tag, sur des images
distinctes. Le rôle contrôle l'unicité du couple `image:tag`, pas du SHA
seul.

## Changer une version

- **Image applicative** → éditer `applications_<service>_sha` dans `vars.yml`,
  puis rejouer `deploy.yml`. Le rôle détecte le changement (fichier `.sha`),
  tire la nouvelle image et redéploie ce seul service.
- **Image socle** → éditer la variable du rôle (ou le template), rejouer
  `provision.yml --tags <role>`.

Détail : [Déploiement › deploy.yml](../deploiement/applications.md).
