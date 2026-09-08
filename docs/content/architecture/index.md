# Architecture

Vue d'ensemble : ce qui tourne, où, et comment les morceaux se parlent.

## Le principe

Tout est conteneurisé, chaque stack a son **projet Docker Compose** déposé
sous `/opt/srv/<stack>/`, et **Traefik** est le seul point d'entrée HTTP. Les
conteneurs se joignent entre eux par des **réseaux Docker externes** partagés,
jamais par des ports publiés sur l'hôte (sauf exceptions d'administration,
liées à la boucle locale).

Ansible génère les `compose.yml` et les `.env` à partir de templates, puis
lance `docker compose up`. **Rien n'est édité à la main sur la VM** : chaque
fichier déployé porte l'en-tête « *ne pas éditer sur l'hôte* ».

## Les stacks

| Stack | Déployée par | Contenu |
|---|---|---|
| **Traefik** | `provision.yml` | routage HTTP, terminaison TLS, métriques |
| **Garage** | `provision.yml` | stockage objet S3 (features), + endpoint web + UI |
| **PostgreSQL** | `provision.yml` | PostgreSQL 17 nu (+ pgweb) — la base de la plateforme |
| **Kafka** | `provision.yml` | broker Kafka KRaft mono-nœud + topics + kafka-ui |
| **MLflow** | `provision.yml` | registre de modèles (image construite sur place) |
| **Monitoring** | `provision.yml` | Prometheus, Grafana, Loki + Promtail, node-exporter, cAdvisor |
| **Applications** | `deploy.yml` | front, api, collector *(chaîne de prédiction en reconstruction autour de Kafka)* |

Détail service par service : [Services](../services/index.md).

## Schéma général

```mermaid
flowchart TB
    subgraph ext[Extérieur]
        U[Navigateur]
        DNS[DNS *.enervision.com]
    end
    U --> T

    subgraph vm[VM on-premise]
        T(Traefik :80 / :443)

        subgraph proxy[proxy_network]
            T
            F[front]
            A[api]
            GW[Garage s3/web]
            GUI[garage-webui]
            GR[Grafana]
        end

        subgraph db[db_network]
            A --- DB[(PostgreSQL)]
        end

        subgraph broker[broker_network]
            C[collector] --> K[(Kafka)]
        end

        subgraph ml[ml_network]
            MLF[MLflow]
        end

        subgraph storage[storage_network]
            GA[(Garage S3)]
        end

        subgraph mon[monitoring_network]
            PR[Prometheus] --> NE[node-exporter]
            PR --> CA[cAdvisor]
            PR --> T
            PT[Promtail] --> LO[Loki]
            GR --> PR
            GR --> LO
        end
    end

    DNS -.résout vers la VM.-> T
```

## Ce qu'Ansible fait — et ne fait pas

| Fait | Ne fait pas |
|---|---|
| Créer les réseaux Docker partagés | Installer Docker |
| Déployer et configurer les stacks | Configurer `/etc/docker/daemon.json` (GPU + snapshotter, géré à la main — voir [L'hôte](hote.md)) |
| Générer les `.env` depuis le Vault | Gérer les paquets système, SSH, le pare-feu |
| Bootstrapper le layout Garage ; construire l'image MLflow sur l'hôte | Construire les images applicatives (dépôts `dashboard`, `api`, `collector`, …) |

## Suite

- [L'hôte](hote.md) — la VM et ses contraintes
- [Réseaux Docker](reseaux.md) — les 6 réseaux, qui s'y branche, qui parle à qui
- [Domaines & routage](domaines.md) — la table domaine → service
