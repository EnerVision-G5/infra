# api — l'API métier

FastAPI / uvicorn. Sert le dashboard : authentification (JWT), lecture des
mesures, archivage des prédictions. Applique le schéma de la base.

| | |
|---|---|
| `kind` | `web` |
| Image | `ghcr.io/enervision-g5/api:<sha>` (dépôt `api`) |
| Conteneur | `enervision-api` |
| Réseaux | `proxy_network`, `db_network`, `ml_network` |
| Port interne | `8080` |
| Route | `api.enervision.com` |
| Healthcheck | `GET /docs` → 200 |

## Migrations au démarrage

L'**entrypoint du conteneur** exécute `alembic upgrade head` avant de lancer
uvicorn. C'est le seul mécanisme qui crée / fait évoluer le schéma de la base
PostgreSQL — voir [Services › PostgreSQL](../postgres.md).

## `.env` généré (`api.env.j2`)

Clés lues par `app/core/config.py` (pydantic-settings, MAJUSCULES) :

| Clé | Vient de | Note |
|---|---|---|
| `APP_NAME` | `applications_api_app_name` | |
| `ENVIRONMENT` | `applications_api_environment` | `production` |
| `DEBUG` | `applications_api_debug` | `false` |
| `AUTH_ENABLED` | `applications_api_auth_enabled` | `true` — seul réglage acceptable en prod |
| `JWT_SECRET` | `applications_api_jwt_secret` → **Vault** | ≥ 32 caractères sinon l'API refuse de démarrer |
| `JWT_ALGORITHM` | `applications_api_jwt_algorithm` | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `applications_api_access_token_expire_minutes` | `60` |
| `DATABASE_URL` | construit par le rôle | dialecte **asyncpg** |
| `CORS_ALLOWED_ORIGINS` | `applications_api_cors_allowed_origins` | l'origine du front, jamais de joker |

## Asserts du rôle

Le déploiement échoue si :

- `applications_api_jwt_secret` est absente ou fait < 32 caractères ;
- `applications_api_cors_allowed_origins` est vide ou contient `*`.

!!! note "Intégration au moteur d'inférence retirée"
    L'API était cliente du service `serving` (routes de synchronisation et de
    simulation de pic) et le job `predict-cron` rafraîchissait la table
    `prediction`. `serving` et `predict-cron` ont été retirés le temps que la
    chaîne ML soit reconstruite autour de Kafka — les variables `PREDICT_*`
    reviendront dans `api.env.j2` à ce moment-là.

## Dépannage

| Symptôme | Piste |
|---|---|
| conteneur en boucle de redémarrage | `JWT_SECRET` absente / trop courte, ou base injoignable, ou migration en échec — `docker logs enervision-api` |
| `relation "…" does not exist` | migrations non appliquées (logs de démarrage) |
| erreur de dialecte SQLAlchemy | `DATABASE_URL` en `psycopg` au lieu d'`asyncpg` |
| appels du dashboard bloqués | `CORS_ALLOWED_ORIGINS` (symétrie avec la CSP du front — voir [front](front.md)) |
