# API

L'API métier FastAPI.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Image api, réseaux proxy_network / db_network / ml_network
- Variables : JWT_SECRET (Vault, >= 32), CORS_ALLOWED_ORIGINS, DATABASE_URL (asyncpg)
- Migrations Alembic appliquées à l'entrypoint du conteneur
- predict-cron : job de rafraîchissement des prédictions, même image, timer
- Dépannage : démarrage, DB, auth
