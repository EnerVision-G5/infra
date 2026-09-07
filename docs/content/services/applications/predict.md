# predict — collector, etl, training, mlflow, serving

Cinq conteneurs déployés par le rôle `applications` à partir des images du
dépôt `predict`. Ce qui suit décrit **leur déploiement** (image, réseaux,
volumes, `.env`, déclenchement) — pas le fonctionnement de la chaîne ML,
documenté côté dépôt `predict`.

La configuration de ces services est un **YAML en couches embarqué dans
l'image** ; les `.env` générés par le rôle ne fournissent que les
`${VARIABLE}` que ce YAML résout.

---

## collector

| | |
|---|---|
| `kind` | `worker` |
| Image | `predict/collector:<sha>` (`applications_collector_sha`) |
| Conteneur | `enervision-collector-poller` |
| Réseau | `db_network` |
| Entrypoint | `python -m collector.poller` |
| `.env` | `PREDICT_ENV`, `DATABASE_URL` (**psycopg**), `MOCK_API_URL` (`applications_collector_mock_api_url`) |
| Volume | aucun |

Rattrapage daté : **timer systemd** `collector-backfill.timer` — `*-*-*
02:30:00`, `--days {{ applications_collector_backfill_days }}` (2). Posé/retiré
par le rôle selon `applications_collector_backfill_active` (collector activé
**et** `applications_collector_backfill_enabled`).

---

## etl

| | |
|---|---|
| `kind` | `worker` |
| Image | `predict/etl:<sha>` (`applications_etl_sha`) |
| Conteneur | `enervision-etl` |
| Réseaux | `db_network`, `storage_network` |
| `.env` | `PREDICT_ENV`, `DATABASE_URL` (**psycopg**), `ETL_PERIOD_SECONDS` (`applications_etl_period_seconds`, 3600), clés S3 |
| Volume | aucun (sortie sur Garage) |

---

## training

| | |
|---|---|
| `kind` | `job` — **jamais** démarré par `docker compose up` |
| Image | `predict/training:<sha>` (`applications_training_sha`) |
| Réseaux | `db_network`, `ml_network`, `storage_network` |
| `.env` | `PREDICT_ENV`, `DATABASE_URL` (**psycopg**), `MLFLOW_TRACKING_URI`, `TRAINING_EXPERIMENT`, clés S3 |
| Déclenchement | **timer systemd** `training.timer` — `{{ applications_training_on_calendar }}` (`Sun *-*-* 03:30:00`), `Persistent=true`, `RandomizedDelaySec=600` |
| Exécution | `docker compose --project-name enervision-training --profile jobs run --rm -T training --history-days 90` |
| `TimeoutStartSec` | `applications_training_timeout_seconds` (7200) |

Posé/retiré selon `applications_training_active` (`'training' in
applications_enabled`).

Le timer **entraîne uniquement**. Mettre une version en service est une
action manuelle :

```bash
cd /opt/srv/applications/training
docker compose --project-name enervision-training --profile jobs \
  run --rm training --promote-version <n>
```

Un déploiement ne réentraîne rien : il met à jour l'image du prochain run.

---

## mlflow

| | |
|---|---|
| `kind` | `web` |
| Image | *= `predict/training`* (`shares_image_with: training`) |
| Conteneur | `enervision-mlflow` |
| Réseaux | `ml_network` (+ `proxy_network` si `applications_mlflow_expose`, + `storage_network` si `applications_mlflow_artifacts_destination` en `s3://`) |
| Port publié | `127.0.0.1:5000` (tunnel SSH) |
| Volume | `mlruns` → `/mlruns` (backend SQLite + artefacts, hors image) |
| Commande | `mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:////mlruns/mlflow.db --artifacts-destination /mlruns/artifacts --allowed-hosts …` |

`--allowed-hosts` liste `enervision-mlflow:5000`, `localhost:5000`,
`127.0.0.1:5000` (+ le domaine public si la route existe) — MLflow 3 renvoie
`403` à tout `Host` inconnu.

**Exposition** : `applications_mlflow_expose` = `true` → route
`mlflow.enervision.com` **avec authentification basique obligatoire**
(`applications_mlflow_basic_auth_users`, format htpasswd, Vault). Le rôle
refuse de déployer la route sans ces identifiants.

Tunnel :

```bash
ssh -p 22 -L 5000:127.0.0.1:5000 root@10.105.200.46   # puis http://localhost:5000
```

---

## serving

| | |
|---|---|
| `kind` | `web` |
| Image | `predict/serving:<sha>` (`applications_serving_sha`) |
| Conteneur | `enervision-serving` |
| Réseaux | `proxy_network`, `ml_network`, `storage_network` — **pas** `db_network` |
| Port interne | `8000` |
| Route | `predict.enervision.com` |
| `.env` | `PREDICT_ENV`, `MLFLOW_TRACKING_URI`, `SERVING_MODEL_URI` (`applications_serving_model_uri`), clés S3 |
| Healthcheck | `GET /health` — non redémarré s'il tombe (laisse lire le journal) |

`serving` démarre même si MLflow est injoignable, et répond alors `503`.

---

## Clés de stockage objet (Garage)

`serving`, `training` et `etl` lisent Garage via les variables **`AWS_*`**
(`AWS_ENDPOINT_URL=http://garage:3900`, région `garage`). Les identifiants
viennent du Vault (`vault_garage_s3_access_key_id` /
`vault_garage_s3_secret_access_key`, produits par `garage key create`).

Le rôle **échoue au déploiement** si `applications_predict_storage_root` est
une URI `s3://` et qu'aucune clé n'est fournie (assert sur l'intersection de
`applications_enabled` avec `serving/training/etl`).

## Dépannage

| Symptôme | Piste |
|---|---|
| `enervision-serving` répond `503` | MLflow injoignable, ou aucun modèle sous l'alias configuré |
| `403` MLflow depuis training/serving | `Host` absent de `--allowed-hosts` |
| `training` tué prématurément | `TimeoutStartSec` — `applications_training_timeout_seconds` |
| `collector` : `connection refused` vers la source | `applications_collector_mock_api_url` faux / source injoignable |
| services predict : *NoCredentialsError* / bucket vide | clés S3 absentes du Vault, ou clé `garage` sans droit sur le bucket |

Les runs d'entraînement passés se lisent dans MLflow ; l'état des timers, dans
`systemctl list-timers`.
