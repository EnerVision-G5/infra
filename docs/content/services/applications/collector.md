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

Le code est aujourd'hui **entièrement hardcodé** :

| Réglage | Valeur (dans le code) |
|---|---|
| Bootstrap Kafka | `kafka:9092` |
| API source | `http://mock-api:8000` |
| Topic | `energy.data.raw` |
| Sites | `SITE001`…`SITE005` |
| Intervalle | 60 s |

Le rôle lance donc l'image **telle quelle**. Le `.env` généré
(`collector.env.j2`) est vide — il accueillera les `${VARIABLE}` quand le
service deviendra configurable.

!!! warning "`mock-api` doit être résoluble"
    Le collector appelle `http://mock-api:8000`. Un conteneur nommé `mock-api`
    doit exister sur l'un des réseaux de `applications_collector_networks`.
    Tant que le mock-api n'a pas son rôle : ajouter son réseau à cette liste,
    ou le déployer sur `broker_network`.

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
| `httpx.ConnectError` vers `mock-api` | `mock-api` non résoluble — voir l'encart ci-dessus |
| aucun message dans `energy.data.raw` | vérifier `docker logs enervision-collector` |
