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

`.env` généré (`/opt/srv/timescaledb/.env`) :

| Clé | Vient de |
|---|---|
| `POSTGRES_DB` | `timescaledb_db` (`enervision`) |
| `POSTGRES_USER` | `timescaledb_user` (`enervision`) |
| `POSTGRES_PASSWORD` | `vault_timescaledb_password` |

`TIMESCALEDB_TELEMETRY=off`. Healthcheck : `pg_isready` sur
`$POSTGRES_USER` / `$POSTGRES_DB`.

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

| Client | Dialecte | DSN (construit par le rôle) |
|---|---|---|
| `api` | asyncpg | `postgresql+asyncpg://<user>:<pass>@timescaledb:5432/<db>` |
| `collector`, `etl`, `training`, `predict-cron` | psycopg | `postgresql+psycopg://<user>:<pass>@timescaledb:5432/<db>` |

`<user>` / `<db>` = `timescaledb_user` / `timescaledb_db`, `<pass>` vient du
Vault. Les deux dialectes **ne sont pas interchangeables**.

## Accès administrateur

Le port est publié sur `127.0.0.1` : `psql` se lance depuis la VM. Les
identifiants sont dans `/opt/srv/timescaledb/.env`. Ce qu'on fait *dans* la
base (schéma, données, comptes) relève des dépôts applicatifs, pas de ce
dépôt.

## Sauvegarde

Toute la donnée vit dans le volume nommé **`timescaledb_data`**, indépendant
de l'image : le sauvegarder au niveau volume, ou faire un dump logique
(`pg_dump` dans le conteneur, en lisant `POSTGRES_USER` / `POSTGRES_DB` de son
environnement).

## Dépannage

| Symptôme | Piste |
|---|---|
| `api` : `relation "…" does not exist` | migrations non appliquées → regarder les logs de démarrage de `enervision-api` |
| `api` : erreur de dialecte au démarrage | `DATABASE_URL` en `psycopg` au lieu d'`asyncpg` |
| connexion refusée depuis un conteneur | le conteneur n'est pas sur `db_network` |
| `psql` depuis l'extérieur de la VM | impossible — le port est lié à `127.0.0.1` |
