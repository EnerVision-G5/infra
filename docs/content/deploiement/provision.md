# provision.yml

Met en place les services socle sur l'hôte. `hosts: all`, `become: true`.

```bash
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass
```

## Déroulé

| Étape | Tag | Détail |
|---|---|---|
| **pre_tasks** — créer les réseaux Docker externes | `always` | boucle sur `docker_external_networks` (7 réseaux), `state: present`. Idempotent. Le tag `always` garantit qu'ils existent même avec `--tags <role>`. |
| rôle `traefik` | `traefik` | `/opt/srv/traefik/` : `compose.yml`, `.env` → `docker compose up` |
| rôle `garage` | `garage` | `/opt/srv/garage/` : `compose.yml`, `.env`, `garage.toml` → `up` → **bootstrap du layout** (idempotent) |
| rôle `postgres` | `postgres`, `database` | `/opt/srv/postgres/` : `compose.yml`, `.env` → `up` (PostgreSQL + pgweb). Base **vide**. |
| rôle `kafka` | `kafka` | `/opt/srv/kafka/` : `compose.yml`, `.env` → `up` (broker KRaft + `kafka-init` pour les topics + kafka-ui) |
| rôle `mlflow` | `mlflow` | `/opt/srv/mlflow/` : `Dockerfile`, `compose.yml`, `.env` → `build` + `up`. Refuse une destination d'artefacts `wasbs://` sans chaîne de connexion Azure. |
| rôle `monitoring` | `monitoring` | `/opt/srv/monitoring/` : compose + configs Prometheus/Loki/Promtail + provisioning Grafana (datasources, dashboards) → `up` |

## Ce qui n'y est plus

Les rôles `base`, `ssh`, `firewall`, `security` et `docker_engine` **ont été
retirés** : la VM est fournie provisionnée. Il ne reste de `docker_engine` que
la création des réseaux, en `pre_tasks`.

`/etc/docker/daemon.json` **n'est pas géré** — voir
[Architecture › L'hôte](../architecture/hote.md).

## Bootstrap du layout Garage

Le rôle `garage` termine par un bloc conditionnel
(`garage_layout_manage: true`) :

1. attend `/garage status` ;
2. si `Current cluster layout version: 0` : `layout assign -z dc1 -c 64G <id>`
   puis `layout apply --version 1`.

Rejouable sans risque (idempotent, ne fait rien si le layout est déjà en
version ≥ 1).

## Idempotence

Chaque rôle **régénère** son `compose.yml` et son `.env` à chaque run
(templates), puis `docker compose up` : si rien n'a changé, aucun conteneur
n'est recréé. Les volumes de données ne sont jamais touchés.

## Vérifications

Les conteneurs socle (`traefik`, `garage`, `postgres`, `kafka`, `mlflow`, la
stack `monitoring`) doivent être `Up`, le nœud Garage doit apparaître dans
`garage status` avec une zone et une capacité, `kafka-init` doit être sorti en
`Exited (0)` après avoir créé les topics, et `grafana.enervision.com` doit
répondre.
