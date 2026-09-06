# deploy.yml

Déploiement et mise à jour des applications.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Bumper une version : éditer `applications_*_sha` dans `vars.yml` avec le tag
  `sha-<git>` publié sur GHCR par le dépôt applicatif (le *comment* l'image
  est construite est documenté dans ce dépôt-là, pas ici)
- Activer / désactiver un service : `applications_enabled`
- Ce que fait le rôle : gate de vérifs, `.env`, `compose.yml`, pull
  conditionnel, `docker compose up`
- Les timers systemd (collector-backfill, training)
