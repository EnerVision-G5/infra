# EnerVision — Base TimescaleDB (schéma figé v1.0)

Cible stable pour l'ETL et l'API. Périmètre gelé : `mesure` (hypertable),
`mesure_exclu`, `prediction`, `modele`, `app_user` (+ `site`, référentiel
requis pour les clés étrangères).

## Démarrage

```bash
cp .env.example .env      # puis changer POSTGRES_PASSWORD
docker compose up -d
docker compose ps         # attendre l'état "healthy"
```

Les scripts de `initdb/` s'exécutent automatiquement **au premier démarrage
uniquement** (volume vide). Pour repartir de zéro : `docker compose down -v`.

## Vérification des critères d'acceptation

```bash
# 1. Extension TimescaleDB activée
docker compose exec timescaledb psql -U enervision -d enervision -c "\dx timescaledb"

# 2. Hypertable sur mesure
docker compose exec timescaledb psql -U enervision -d enervision \
  -c "SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;"

# 3. Les 6 tables présentes
docker compose exec timescaledb psql -U enervision -d enervision -c "\dt"

# 4. Insertion de test (puis nettoyage)
docker compose exec timescaledb psql -U enervision -d enervision -c "
  INSERT INTO mesure (ts, site_id, consumption_kw, data_quality)
  VALUES (now(), 'SITE001', 87.34, 'good');
  SELECT * FROM mesure; DELETE FROM mesure;"
```

## Points de conception à relire (revue API + Data)

- **PK composite `(site_id, ts)` sur `mesure`** — imposé par TimescaleDB :
  toute contrainte unique d'une hypertable doit inclure la colonne de
  partitionnement. Conséquence pour l'ETL : idempotence via
  `ON CONFLICT (site_id, ts) DO NOTHING`.
- **`mesure_exclu` référence `(site_id, ts)`** — FK vers une hypertable,
  supportée depuis TimescaleDB 2.16 (image épinglée : 2.17.2).
- **Chunks de 7 jours** sur `mesure` (`chunk_time_interval`).
- **NULL conservés** avec `null_reasons` + `data_quality` (conseil ETL de
  la doc API : ne jamais filtrer les NULL).
- **`prediction` en table classique** — volumétrie faible ; conversion en
  hypertable possible plus tard par migration.
- **Seed `site`** : SITE004–007 sont des placeholders, l'ETL doit faire un
  UPSERT depuis `GET /api/v1/sites` au démarrage.

## Migrations appliquées

| Fichier | Objet |
|---|---|
| `initdb/01_schema.sql` | schéma figé v1.0 |
| `initdb/02_seed_sites.sql` | référentiel des 7 sites |
| `initdb/03_mesure_imputation.sql` | colonnes d'imputation sur `mesure` (EV-08) |
| `initdb/04_app_user_auth.sql` | comptes locaux et rôles `reader` / `writer` (EV-12) |

Les scripts d'`initdb/` ne sont pas rejoués sur une base déjà démarrée : les
migrations sont idempotentes, il suffit de les appliquer à la main.

```bash
docker compose exec timescaledb \
    psql -U enervision -d enervision \
    -f /docker-entrypoint-initdb.d/04_app_user_auth.sql
```

### Authentification (EV-12)

`app_user` ne fédère plus une identité externe : ADR-009 a retenu le flux
OAuth2 mot de passe avec des JWT signés par l'API, et acté que les mots de
passe sont stockés hachés. Un **compte local** est donc une ligne avec :

| Colonne | Contenu |
|---|---|
| `oauth_provider` | `'local'` |
| `oauth_subject` | le `username`, publié tel quel dans `UserOut.username` et dans le claim `sub` du JWT |
| `password_hash` | hachage **argon2id**, produit par l'API ou par le seed de dev |
| `role` | `reader` ou `writer`, valeurs du contrat gelé |

La clé de connexion est la contrainte `UNIQUE (oauth_provider, oauth_subject)`
déjà présente au schéma v1.0. Une fédération réelle resterait possible sous un
autre `oauth_provider`, sans nouvelle migration.

## Utilisateurs de développement

`dev-seed/dev_users.py` produit le SQL créant deux comptes, `dev.reader` et
`dev.writer`. Il **écrit sur la sortie standard** sans toucher la base : le SQL
est relisible avant d'être appliqué, et aucun pilote de base n'est nécessaire.

```bash
pip install -r enervision-db/dev-seed/requirements.txt

DEV_USERS_PASSWORD='mon-mot-de-passe' \
    python enervision-db/dev-seed/dev_users.py \
    | docker compose exec -T timescaledb psql -U enervision -d enervision
```

Le mot de passe n'est jamais écrit dans le dépôt : il est lu dans
`DEV_USERS_PASSWORD` et haché au moment de la génération. Sans la variable, le
défaut est `changeme-dev`, et le script le signale sur `stderr`. Le SQL produit
est un `UPSERT` : le rejouer est aussi le moyen de changer le mot de passe de
ces deux comptes.

Ce fichier est **hors de `initdb/`** à dessein : les scripts d'`initdb`
s'exécutent au premier démarrage de n'importe quelle base, production comprise,
et deux comptes dont le mot de passe est connu du dépôt n'y ont pas leur place.
L'appliquer demande un geste explicite.

### Pourquoi un script Python et non un fichier `.sql`

Les mots de passe sont hachés en **argon2id**, et PostgreSQL ne sait pas le
faire : son extension `pgcrypto` ne propose que bcrypt, md5, des et xdes.
Produire les hachages avec une autre bibliothèque que celle de l'API ferait
reposer la connexion sur la compatibilité de deux implémentations distinctes.
Le script utilise donc exactement la même, `argon2-cffi`, épinglée à la même
version, avec les mêmes paramètres par défaut qu'`app/password.py` côté API.

## Règle d'évolution

Le schéma est figé : toute modification passe par un nouveau fichier de
migration `initdb/NN_description.sql` (ou un outil type Flyway/Alembic),
jamais par l'édition de `01_schema.sql`.
