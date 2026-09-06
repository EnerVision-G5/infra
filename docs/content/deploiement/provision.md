# provision.yml

Met en place les services socle sur l'hôte. `hosts: all`, `become: true`.

```bash
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass
```

## Déroulé

| Étape | Tag | Détail |
|---|---|---|
| **pre_tasks** — créer les réseaux Docker externes | `always` | boucle sur `docker_external_networks` (6 réseaux), `state: present`. Idempotent. Le tag `always` garantit qu'ils existent même avec `--tags <role>`. |
| rôle `traefik` | `traefik` | `/opt/srv/traefik/` : `compose.yml`, `.env` → `docker compose up` |
| rôle `garage` | `garage` | `/opt/srv/garage/` : `compose.yml`, `.env`, `garage.toml` → `up` → **bootstrap du layout** (idempotent) |
| rôle `timescaledb` | `timescaledb`, `database` | `/opt/srv/timescaledb/` : `compose.yml`, `.env` → `up`. Base **vide**. |
| rôle `monitoring` | `monitoring` | `/opt/srv/monitoring/` : compose + configs Prometheus/Loki/Promtail + provisioning Grafana (datasources, dashboards) → `up` |

## Ce qui n'y est plus

Les rôles `base`, `ssh`, `firewall`, `security` et `docker_engine` **ont été
retirés** : la VM est fournie provisionnée. Il ne reste de `docker_engine` que
la création des réseaux, en `pre_tasks`.

`/etc/docker/daemon.json` **n'est pas géré** — voir
[runbook](../exploitation/docker-daemon.md).

## Bootstrap du layout Garage

Le rôle `garage` termine par un bloc conditionnel
(`garage_layout_manage: true`) :

1. attend `/garage status` ;
2. si `Current cluster layout version: 0` : `layout assign -z dc1 -c 64G <id>`
   puis `layout apply --version 1`.

Rejouable sans risque. Détail : [runbook layout Garage](../exploitation/garage-layout.md).

## Idempotence

Chaque rôle **régénère** son `compose.yml` et son `.env` à chaque run
(templates), puis `docker compose up` : si rien n'a changé, aucun conteneur
n'est recréé. Les volumes de données ne sont jamais touchés.

## Vérifications rapides

```bash
docker ps --format '{{.Names}}\t{{.Status}}'
docker exec garage /garage status
docker exec timescaledb pg_isready -U enervision -d enervision
curl -sI http://grafana.enervision.com     # via la VM
```
