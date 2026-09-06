# Réseaux Docker

Les stacks ne se joignent jamais par des ports publiés sur l'hôte, mais par
des **réseaux Docker externes** partagés entre projets Compose.

## Création

Les réseaux sont déclarés dans `docker_external_networks` (`group_vars`) et
créés à deux endroits, tous deux idempotents :

- `provision.yml` — en `pre_tasks`, tag `always` (donc même avec `--tags`
  ciblé, ils existent avant les rôles) ;
- rôle `applications` — au début de `deploy.yml`.

Un projet Compose les référence en `external: true` : il **ne les crée pas**,
il s'y attache.

## Les six réseaux

| Réseau | Rôle | Qui s'y attache |
|---|---|---|
| `proxy_network` | exposition via Traefik | traefik, front, api, serving, grafana, garage, garage-webui, mlflow *(si exposé)* |
| `db_network` | accès à TimescaleDB | timescaledb, api, collector, etl, predict-cron, training |
| `ml_network` | registre MLflow + appels `api ↔ serving` | api, serving, mlflow, training, predict-cron |
| `storage_network` | stockage objet Garage (S3) | garage, serving, etl, training, mlflow *(si artefacts sur `s3://`)* |
| `monitoring_network` | collecte des métriques | prometheus, grafana, loki, promtail, node-exporter, cadvisor, traefik |
| `api_network` | *(réservé)* | — actuellement créé mais aucun service ne l'utilise |

## Schéma

```mermaid
flowchart LR
    subgraph proxy_network
        TR(traefik)
        FR[front]
        AP[api]
        SV[serving]
        GRA[grafana]
        GAR[garage]
    end
    subgraph db_network
        DB[(timescaledb)]
        AP2[api]
        CO[collector]
        ET[etl]
        PC[predict-cron]
    end
    subgraph ml_network
        AP3[api]
        SV2[serving]
        MLF[mlflow]
        TRN[training]
    end
    subgraph storage_network
        GAR2[garage]
        SV3[serving]
        ET2[etl]
        TRN2[training]
    end
    subgraph monitoring_network
        PROM[prometheus]
        GRA2[grafana]
        LOKI[loki]
        PROMT[promtail]
        NE[node-exporter]
        CAD[cadvisor]
        TR2[traefik]
    end
```

*(un même conteneur apparaît dans plusieurs sous-graphes : il est attaché à
plusieurs réseaux.)*

## Résolution de noms entre projets

Chaque application a son **propre projet Compose** (`enervision-<name>`).
L'alias de service Compose (`front`, `api`…) n'est visible que dans son
projet. D'un projet à l'autre, c'est le **`container_name`** qui résout, sur
le réseau partagé :

| Alias inter-projets | Conteneur |
|---|---|
| `enervision-serving:8000` | service d'inférence |
| `enervision-mlflow:5000` | registre MLflow |
| `timescaledb:5432` | base |
| `garage:3900` | endpoint S3 |

La matrice complète : [Référence › Réseaux & ports](../reference/reseaux-ports.md).
