# Applications

Le rôle Ansible applications : un compose par service, versionné par SHA.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Le catalogue (applications_services_catalog) et applications_enabled
- Les kinds : web (Traefik), worker (long, sans port), job (timer systemd)
- shares_image_with (mlflow sur l'image training, predict-cron sur l'image api)
- Versioning : applications_*_sha dans vars.yml, images GHCR sha-<git>
- Génération : .env + compose.yml par service, pull si SHA changé, docker compose up
