# deploy.yml

Déploiement et mise à jour des applications.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Bumper une version : éditer applications_*_sha dans vars.yml
- Activer / désactiver un service : applications_enabled
- Ce que fait le rôle : gate de vérifs, .env, compose, pull conditionnel, up
- Les timers systemd (collector-backfill, training)
