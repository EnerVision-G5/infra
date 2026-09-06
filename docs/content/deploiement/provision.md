# provision.yml

Mise en place des services socle sur l'hôte.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- pre_tasks : création des réseaux Docker partagés (tag always)
- Rôles : traefik, garage, timescaledb, monitoring
- Tags disponibles
- Idempotence, ce qui est régénéré à chaque run
