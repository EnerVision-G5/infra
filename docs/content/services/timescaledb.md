# TimescaleDB

PostgreSQL + TimescaleDB : la base de la plateforme.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Image épinglée, volume timescaledb_data, réseau db_network, port loopback
- Le schéma est porté par les migrations Alembic du dépôt api — jamais par ce rôle
- Accès (psql), variables (db.env, mot de passe via Vault)
- Sauvegarde / restauration du volume — renvoi vers Exploitation
