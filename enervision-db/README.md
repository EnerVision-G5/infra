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
| `initdb/05_prediction_contrat.sql` | les trois champs du contrat absents de `prediction` (EV-38) |
| `initdb/06_ingestion_etat.sql` | état courant de la collecte, une ligne par site (EV-18) |
| `initdb/07_mesure_quality_source.sql` | qui a qualifié la mesure, source ou ETL (EV-18) |

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
| `password_hash` | hachage bcrypt, produit par l'API ou par le seed de dev |
| `role` | `reader` ou `writer`, valeurs du contrat gelé |

La clé de connexion est la contrainte `UNIQUE (oauth_provider, oauth_subject)`
déjà présente au schéma v1.0. Une fédération réelle resterait possible sous un
autre `oauth_provider`, sans nouvelle migration.

### Prédictions (EV-38)

Le contrat publie six champs par point de prévision. **Trois étaient déjà là**,
sous un autre nom ou par normalisation :

| Champ du contrat | Où il est |
|---|---|
| `timestamp` | `prediction.ts_cible` |
| `predicted_consumption_kw` | `prediction.consumption_kw_predite` |
| `model_version` | `modele.version`, par le join sur `prediction.modele_id` |

`model_version` **n'est pas ajouté** comme colonne : c'est exactement la même
valeur. Le service d'inférence la lit dans le registre MLflow et
l'entraînement repose cette même version dans `modele` à la promotion. Une
colonne de plus dupliquerait un fait déjà porté, avec le risque ordinaire des
doublons : deux valeurs qui divergent et plus personne pour dire laquelle fait
foi. `modele_id` reste donc `NOT NULL`, c'est ce qui garantit que le join
aboutit.

Un seul cas rend le join muet : un modèle chargé par chemin d'artefact au lieu
d'un alias n'a pas d'entrée de registre, et le service retombe alors sur son
identifiant interne, qui ne correspond à aucune ligne de `modele`. C'est un
déploiement dégradé, pas le cas nominal.

**Les trois qui manquaient vraiment**, ajoutés par la migration :

| Colonne | Pourquoi elle n'existait nulle part |
|---|---|
| `generated_at` | les quatre `TIMESTAMPTZ` du schéma datent tous autre chose : `created_at` l'insertion, `ts_cible` l'heure prévue, `modele.date_entrainement` le run, `mesure.inserted_at` le chargement d'une mesure |
| `lower_bound_kw`, `upper_bound_kw` | non reconstructibles : la bande vaut `valeur ± 1.96 × residual_std × √step`, et `residual_std` est un tag de version MLflow sans colonne dans `modele`, tandis que `step` se compte depuis la dernière mesure observée, origine que rien ne conserve |

`created_at` est le faux ami de la série : l'écart avec l'heure réelle de
production est de quelques millisecondes quand l'archivage suit la prévision,
et se creuse dès qu'il est rejoué, mis en lot ou repris après incident.

Les bornes sont **nullables** : le service rend `null` quand le tag
`residual_std` manque, et forcer une valeur ferait passer « pas d'intervalle »
pour « intervalle de largeur nulle », c'est-à-dire une prévision annoncée comme
certaine.

La clé d'unicité `(modele_id, site_id, ts_cible)` du schéma v1.0 est
**inchangée** : une prévision par modèle, site et instant cible, le job y
reposant la plus fraîche.

### Fraîcheur d'ingestion (EV-18)

`mesure.inserted_at` dit quand une ligne est entrée, et cela suffit **tant
qu'il y a des lignes**. Un capteur mort en produit encore — nulles, avec leurs
`null_reasons` — donc `max(inserted_at)` avance et l'agrégat fonctionne. Mais
un poller arrêté, une source qui répond 500 ou une base injoignable n'en
produisent aucune : `max(inserted_at)` se fige alors exactement comme si le
site avait cessé d'exister. Aucune requête sur `mesure` ne distingue « la
collecte a tourné et il n'y avait rien » de « la collecte n'a pas tourné ».

`ingestion_etat` porte cette distinction, **une ligne par site**, écrite en
UPSERT par les deux points d'entrée du collecteur :

| Colonne | Ce qu'elle permet de voir |
|---|---|
| `last_attempt_at` / `last_success_at` | égales, la collecte va bien ; écartées, elle tourne et échoue ; les deux figées, le collecteur ne tourne plus |
| `last_data_lag_s` | âge de la mesure servie par la source, mesuré par le collecteur — pas reconstructible depuis `inserted_at - ts`, qui mélange retard de source et retard d'écriture |
| `consecutive_failures` | l'à-coup contre la panne installée ; remis à zéro par un succès |
| `source` | `poller` ou `backfill` : un rattrapage manuel ne doit pas se faire passer pour une collecte vivante |

Pas de journal par tick : sept sites à la minute feraient dix mille lignes par
jour à purger, pour une question qui est au présent. L'historique du retard est
déjà dans le journal du collecteur, et EV-30 le porte vers Prometheus.

`mesure.quality_source` répond au second angle mort. `data_quality` est
`NOT NULL DEFAULT 'good'` : le collecteur retombe sur `good` quand la source se
tait, et c'est l'ETL qui repose la vraie qualification. Sans marqueur, une
journée fraîchement collectée affiche **0 % de mesures dégradées** et le site
paraît parfait. `quality_source` vaut `source` tant que l'ETL n'est pas passé,
`etl` ensuite — et le `DO UPDATE` de l'ETL la repose à chaque rejeu.

## Utilisateurs de développement

`dev-seed/01_dev_users.sql` crée deux comptes, `dev.reader` et `dev.writer`.
Il est **hors de `initdb/`** à dessein : les scripts d'`initdb` s'exécutent au
premier démarrage de n'importe quelle base, production comprise, et deux
comptes dont le mot de passe est connu du dépôt n'y ont pas leur place.
L'appliquer demande un geste explicite.

```bash
docker compose exec -e DEV_USERS_PASSWORD='mon-mot-de-passe' timescaledb \
    psql -U enervision -d enervision -f /dev-seed/01_dev_users.sql
```

Le mot de passe n'est jamais écrit dans le dépôt : il est lu dans
`DEV_USERS_PASSWORD` et haché par `pgcrypto` au moment du seed, en bcrypt coût
12, interchangeable avec un hachage produit par l'API. Sans la variable, le
défaut est `changeme-dev`. Rejouer le script est aussi le moyen de changer le
mot de passe de ces deux comptes.

## Règle d'évolution

Le schéma est figé : toute modification passe par un nouveau fichier de
migration `initdb/NN_description.sql` (ou un outil type Flyway/Alembic),
jamais par l'édition de `01_schema.sql`.
