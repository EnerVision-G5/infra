# Services

Une page par stack. Toutes suivent le même gabarit : rôle, image, réseaux,
volumes, configuration, endpoints, points d'attention, dépannage.

| Stack | Déployée par | Page |
|---|---|---|
| Traefik | `provision.yml` | [traefik](traefik.md) |
| Garage | `provision.yml` | [garage](garage.md) |
| TimescaleDB | `provision.yml` | [timescaledb](timescaledb.md) |
| Monitoring | `provision.yml` | [monitoring](monitoring.md) |
| Applications | `deploy.yml` | [applications](applications/index.md) — front, api, et la chaîne predict |

## Conventions communes

- Chaque stack a un dossier `/opt/srv/<stack>/` sur l'hôte : `compose.yml`,
  `.env`, parfois des fichiers de config. **Tous générés**, en-tête « *ne pas
  éditer sur l'hôte* ».
- Déploiement : `community.docker.docker_compose_v2` avec `state: present`
  (idempotent).
- `restart: unless-stopped` partout — un arrêt volontaire n'est pas défait au
  redémarrage du démon.
- Les images socle sont **épinglées** (voir [Référence › Versions](../reference/versions.md)).
