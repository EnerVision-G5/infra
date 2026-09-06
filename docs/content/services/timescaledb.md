# TimescaleDB

PostgreSQL 16 + extension TimescaleDB. La base de toute la plateforme : mesures
brutes, imputations, prédictions archivées, comptes utilisateurs.

| | |
|---|---|
| Rôle Ansible | `timescaledb` (`provision.yml`) |
| Image | `timescale/timescaledb:2.17.2-pg16` |
| Dossier hôte | `/opt/srv/timescaledb/` |
| Réseau | `db_network` uniquement |
| Volume | `timescaledb_data` → `/var/lib/postgresql/data` |
| Port publié | `127.0.0.1:5432` (loopback, administration `psql`) |
| Ressources | 2 Go RAM, 2 CPU (`deploy.resources.limits`) |

## Configuration

`.env` : `POSTGRES_DB=enervision`, `POSTGRES_USER=enervision`,
`POSTGRES_PASSWORD` (Vault). `TIMESCALEDB_TELEMETRY=off`.

Healthcheck : `pg_isready -U enervision -d enervision`.

## Le schéma n'est PAS géré ici

!!! important "Le schéma appartient au dépôt `api`"
    Le rôle déploie un PostgreSQL **nu**. Le schéma (tables, hypertables,
    contraintes, index) est porté par les **migrations Alembic du dépôt
    `api`**, appliquées par l'**entrypoint du conteneur `api`** à chaque
    démarrage.

    Il n'y a **aucune migration dans ce dépôt**, et le rôle ne monte aucun
    script d'init.

Conséquence à l'ordre de déploiement : `provision.yml` (base vide) →
`deploy.yml` (l'`api` démarre, applique `alembic upgrade head`, puis sert).

## Qui se connecte

| Client | Dialecte | DSN |
|---|---|---|
| `api` | asyncpg | `postgresql+asyncpg://…@timescaledb:5432/enervision` |
| `collector`, `etl`, `training`, `predict-cron` | psycopg | `postgresql+psycopg://…@timescaledb:5432/enervision` |

Les deux dialectes **ne sont pas interchangeables**.

## Accès administrateur

```bash
# sur la VM
docker exec -it timescaledb psql -U enervision -d enervision
# ou via le port loopback
psql -h 127.0.0.1 -U enervision -d enervision
```

Inspection, ajout d'un utilisateur applicatif, sauvegarde :
[runbook base de données](../exploitation/base-de-donnees.md).

## Dépannage

| Symptôme | Piste |
|---|---|
| `api` : `relation "…" does not exist` | migrations non appliquées → regarder les logs de démarrage de `enervision-api` |
| `api` : erreur de dialecte au démarrage | `DATABASE_URL` en `psycopg` au lieu d'`asyncpg` |
| connexion refusée depuis un conteneur | le conteneur n'est pas sur `db_network` |
| `psql` depuis l'extérieur de la VM | impossible — le port est lié à `127.0.0.1` |

```bash
docker logs timescaledb --tail 30
docker exec timescaledb pg_isready -U enervision -d enervision
docker exec -it timescaledb psql -U enervision -d enervision -c '\dt'
```
