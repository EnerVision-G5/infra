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

## Les sept réseaux

| Réseau | Rôle | Qui s'y attache |
|---|---|---|
| `proxy_network` | exposition via Traefik | traefik, front, api, grafana, garage, garage-webui |
| `db_network` | accès à PostgreSQL | postgres, pgweb, api |
| `broker_network` | bus Kafka | kafka, kafka-init, kafka-ui, collector |
| `ml_network` | registre MLflow | mlflow |
| `storage_network` | stockage objet Garage (S3) | garage |
| `monitoring_network` | collecte des métriques | prometheus, grafana, loki, promtail, node-exporter, cadvisor, traefik |
| `api_network` | *(réservé)* | — créé mais aucun service ne l'utilise |

`ml_network` et `storage_network` sont quasi vides pour l'instant : la chaîne
de prédiction (serving / training / etl) qui les peuplait est en cours de
reconstruction autour de Kafka.

## Schéma

```mermaid
flowchart LR
    subgraph proxy_network
        TR(traefik)
        FR[front]
        AP[api]
        GRA[grafana]
        GAR[garage]
    end
    subgraph db_network
        DB[(postgres)]
        AP2[api]
    end
    subgraph broker_network
        KFK[kafka]
        KUI[kafka-ui]
        CO[collector]
    end
    subgraph ml_network
        MLF[mlflow]
    end
    subgraph storage_network
        GAR2[garage]
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
| `postgres:5432` | base |
| `kafka:9092` | broker Kafka |
| `mlflow:5000` | registre MLflow (rôle `mlflow`) |
| `garage:3900` | endpoint S3 |

## Dépendances entre conteneurs

Ce qui doit être joignable pour qu'un conteneur fonctionne — utile pour
diagnostiquer un service qui démarre mais ne sert pas.

| Conteneur | Doit joindre | Réseau |
|---|---|---|
| `enervision-api` | `postgres:5432` | `db_network` |
| `enervision-front` | *(rien en interne — le navigateur appelle l'API directement)* | `proxy_network` |
| `enervision-collector` | `kafka:9092`, `mock-api:8000` | `broker_network` |
| `kafka-init` | `kafka:9092` | `broker_network` |
| `mlflow` | Azure Blob (`*.blob.core.windows.net`, HTTPS sortant) *(si artefacts `wasbs://`)* | `ml_network` |
| `traefik` | le socket Docker (`/var/run/docker.sock`) + tous les conteneurs routés sur `proxy_network` | `proxy_network`, `monitoring_network` |
| `prometheus` | `node-exporter:9100`, `cadvisor:8080`, `traefik:8082` | `monitoring_network` |
| `promtail` | le socket Docker, `loki:3100` | `monitoring_network` |

La matrice réseaux/ports complète : [Référence › Réseaux & ports](../reference/reseaux-ports.md).
