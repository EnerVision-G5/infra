# PostgreSQL

PostgreSQL 17, moteur nu. La base de toute la plateforme : mesures brutes,
imputations, prédictions archivées, comptes utilisateurs.

| | |
|---|---|
| Rôle Ansible | `postgres` (`provision.yml`) |
| Image | `postgres:17.10-alpine3.24` |
| Dossier hôte | `/opt/srv/postgres/` |
| Réseau | `db_network` uniquement |
| Volume | `postgres_data` → `/var/lib/postgresql/data` |
| Port publié | `127.0.0.1:5432` (loopback, administration `psql`) |
| Ressources | 2 Go RAM, 2 CPU (`deploy.resources.limits`) |

## Configuration

`.env` généré (`/opt/srv/postgres/.env`) :

| Clé | Vient de |
|---|---|
| `POSTGRES_DB` | `postgres_db` (`enervision`) |
| `POSTGRES_USER` | `postgres_user` (`enervision`) |
| `POSTGRES_PASSWORD` | `vault_postgres_password` |

Healthcheck : `pg_isready` sur `$POSTGRES_USER` / `$POSTGRES_DB`.

## pgweb (console temporaire)

Le rôle déploie aussi **pgweb** (`sosedoff/pgweb`), publié sur
`127.0.0.1:8081`. Console SQL consultée par tunnel SSH :

```
ssh -L 8081:127.0.0.1:8081 <hote>   puis http://localhost:8081
```

Jamais routée par Traefik. À retirer une fois la phase de développement finie
(`postgres_pgweb_enabled: false`, puis `provision.yml --tags postgres`).

## Le schéma n'est PAS géré ici

!!! important "Le schéma appartient au dépôt `api`"
    Le rôle déploie un PostgreSQL **nu**. Le schéma (tables, contraintes,
    index) est porté par les **migrations Alembic du dépôt `api`**, appliquées
    par l'**entrypoint du conteneur `api`** à chaque démarrage.

    Il n'y a **aucune migration dans ce dépôt**, et le rôle ne monte aucun
    script d'init.

Conséquence à l'ordre de déploiement : `provision.yml` (base vide) →
`deploy.yml` (l'`api` démarre, applique `alembic upgrade head`, puis sert).

## Qui se connecte

| Client | Dialecte | DSN (construit par le rôle `applications`) |
|---|---|---|
| `api` | asyncpg | `postgresql+asyncpg://<user>:<pass>@postgres:5432/<db>` |

`<user>` / `<db>` = `postgres_user` / `postgres_db`, `<pass>` vient du Vault.
L'hôte `postgres` est le nom de conteneur du rôle, résolu sur `db_network`.

Les services de la chaîne ML reconstruite (ingester, …) ouvriront la base en
**psycopg** (synchrone) — un dialecte non interchangeable avec asyncpg.

## Accès administrateur

Le port est publié sur `127.0.0.1` : `psql` se lance depuis la VM (ou par
tunnel SSH). Les identifiants sont dans `/opt/srv/postgres/.env`.

## Sauvegarde

Toute la donnée vit dans le volume nommé **`postgres_data`**, indépendant de
l'image : le sauvegarder au niveau volume, ou faire un dump logique (`pg_dump`
dans le conteneur, en lisant `POSTGRES_USER` / `POSTGRES_DB` de son
environnement).

## Dépannage

| Symptôme | Piste |
|---|---|
| `api` : `relation "…" does not exist` | migrations non appliquées → logs de démarrage de `enervision-api` |
| `api` : erreur de dialecte au démarrage | `DATABASE_URL` en `psycopg` au lieu d'`asyncpg` |
| connexion refusée depuis un conteneur | le conteneur n'est pas sur `db_network`, ou vise encore l'ancien hôte `timescaledb` |
| `psql` depuis l'extérieur de la VM | impossible — le port est lié à `127.0.0.1` |
