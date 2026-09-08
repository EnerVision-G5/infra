# Kafka

Broker Apache Kafka en mode **KRaft** (pas de ZooKeeper), mono-nœud : le même
conteneur porte le rôle *broker* et le rôle *controller*.

| | |
|---|---|
| Rôle Ansible | `kafka` (`provision.yml`) |
| Images | `apache/kafka:3.9.2`, `ghcr.io/kafbat/kafka-ui:v1.5.0` |
| Dossier hôte | `/opt/srv/kafka/` |
| Réseau | `broker_network` uniquement |
| Volume | `kafka_data` → `/var/lib/kafka/data` |
| Port publié | aucun par défaut (voir plus bas) ; `127.0.0.1:8080` pour kafka-ui |
| Ressources | broker 1 Go / 1 CPU, kafka-ui 256 Mo / 0.25 CPU |

## Services du compose

| Service | Rôle |
|---|---|
| `kafka` | broker + controller KRaft |
| `kafka-init` | job ponctuel (`restart: "no"`) : attend le broker, crée les topics (`--if-not-exists`), sort |
| `kafka-ui` | console web temporaire (tunnel SSH) |

## Topics

Créés au démarrage par `kafka-init`, à partir de `kafka_topics`
(`defaults/main.yml`) :

| Topic | Partitions | Réplication |
|---|---|---|
| `energy.data.raw` | 1 | 1 |
| `energy.data.enriched` | 1 | 1 |

Ajouter un topic = ajouter une entrée à `kafka_topics` dans `group_vars`, puis
`provision.yml --tags kafka`. La création est idempotente.

## Écoute réseau

Le broker n'annonce qu'un listener interne : `PLAINTEXT://kafka:9092`. Les
clients conteneurisés le joignent par le nom `kafka` sur `broker_network`.

Un client **hors** du réseau Docker ne peut pas s'y connecter par un simple
bind loopback : l'annonce `kafka:9092` ne se résout pas côté hôte. Pour
inspecter le cluster, passer par **kafka-ui** :

```
ssh -L 8080:127.0.0.1:8080 <hote>   puis http://localhost:8080
```

`kafka_publish_broker: true` ajoute le mapping `127.0.0.1:9092` — utile pour un
`kafka-*.sh` lancé *depuis la VM elle-même*, pas pour un client distant.

kafka-ui et le broker publié sont des **facilités de développement** : à
retirer (`kafka_ui_enabled: false`, `kafka_publish_broker: false`) une fois la
phase de dev finie.

## Persistance

`KAFKA_LOG_DIRS=/var/lib/kafka/data` sur le volume nommé `kafka_data` :
`CLUSTER_ID` est fixe (`kafka_cluster_id`), le stockage est formaté une seule
fois et un redéploiement retrouve le même cluster.

## Dépannage

| Symptôme | Piste |
|---|---|
| `kafka-init` boucle sur « Attente de Kafka » | broker pas encore *healthy* — regarder `docker logs kafka` |
| client : `UnknownHostException: kafka` | le client n'est pas sur `broker_network` |
| `kafka-*.sh` depuis l'hôte : timeout | broker non publié (`kafka_publish_broker`) ou annonce non résoluble — utiliser kafka-ui |
| cluster « vide » après redéploiement | volume `kafka_data` recréé, ou `CLUSTER_ID` changé |
