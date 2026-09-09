# collector

Poller d'ingestion : interroge l'API mock au fil de l'eau et pousse les mesures
dans **Kafka** (topic `energy.data.raw`). Premier maillon de la chaîne
événementielle qui remplace l'ancien `predict/*`.

| | |
|---|---|
| `kind` | `worker` (processus long, sans port ni route) |
| Dépôt | `collector` |
| Image | `ghcr.io/enervision-g5/collector:{{ applications_collector_sha }}` |
| Conteneur | `enervision-collector` |
| Réseaux | `applications_collector_networks` — `broker_network` par défaut |
| Volume | aucun |
| Ressources | 256 Mo RAM, 0.5 CPU |

## Configuration

Lue de l'environnement (`os.getenv`), via le `.env` généré
(`collector.env.j2`) :

| Clé | Variable Ansible | Défaut |
|---|---|---|
| `MOCK_API_URL` | `applications_collector_mock_api_url` | `http://mock-api:8000` — **surchargé dans `group_vars`** |
| `KAFKA_BOOTSTRAP` | `applications_collector_kafka_bootstrap` | `kafka:9092` |
| `KAFKA_TOPIC` | `applications_collector_kafka_topic` | `energy.data.raw` |
| `POLL_INTERVAL` | `applications_collector_poll_interval` | `60` |
| `SITES` (CSV) | `applications_collector_sites` | `SITE001…SITE005` |

L'API mock n'est **pas** un conteneur : c'est une adresse sur le réseau de
l'hôte (aujourd'hui `http://192.168.8.180:8000`). Le collector la joint
directement — le trafic sort par la passerelle Docker de l'hôte, aucun réseau
Docker supplémentaire n'est nécessaire.

## Déploiement

Suit le flux standard du rôle `applications` :

1. workflow `cd.yml` du dépôt `collector` (push sur `master`) → image
   `ghcr.io/enervision-g5/collector:sha-<git-sha>` sur le GHCR ;
2. reporter ce `sha-…` dans `applications_collector_sha` (`group_vars`), et
   ajouter `collector` à `applications_enabled` ;
3. `ansible-playbook deploy.yml`.

## backfill

Le dépôt porte aussi `backfill.py` (génère un historique minute et le pousse
dans le même topic) : `python backfill.py --days 10` dans le conteneur. Pas
d'unité systemd — c'est une opération ponctuelle d'amorçage.

## Dépannage

| Symptôme | Piste |
|---|---|
| `NoBrokersAvailable` / timeout Kafka | conteneur pas sur `broker_network`, ou broker down |
| `httpx.ConnectError` vers l'API mock | `MOCK_API_URL` faux, hôte injoignable, ou pare-feu entre la VM et cette adresse |
| aucun message dans `energy.data.raw` | vérifier `docker logs enervision-collector` |
