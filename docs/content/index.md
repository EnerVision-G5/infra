# Infrastructure EnerVision

Documentation technique de la plateforme **on-premise** EnerVision : ce qui
tourne sur la VM de l'école, comment c'est déployé, et comment l'exploiter.

!!! info "État de cette documentation — phase 1"
    Le squelette et la stack MkDocs sont en place. Les pages ci-dessous sont
    des **ébauches** : chacune liste ce qu'elle contiendra. Le remplissage se
    fait onglet par onglet dans les phases suivantes.

## En bref

- Plateforme **intégralement on-premise**, en conteneurs Docker Compose
  derrière **Traefik**, déployée par **Ansible**.
- La VM de l'école est fournie **déjà provisionnée** (Docker, GPU,
  durcissement système) : Ansible ne fait que déployer les stacks.
- Deux playbooks : `provision.yml` (Traefik, Garage, TimescaleDB, monitoring
  + réseaux Docker partagés) et `deploy.yml` (les applications).
- Les images applicatives (front, api, predict) sont construites par les
  pipelines de leurs dépôts et publiées sur GHCR, épinglées par SHA de commit.

## Par où commencer

| Profil | Aller voir |
|---|---|
| Découvrir la plateforme | [Architecture](architecture/index.md) |
| Déployer / mettre à jour | [Déploiement](deploiement/index.md) |
| Un incident en cours | [Exploitation](exploitation/index.md) |
| Une valeur précise (port, variable…) | [Référence](reference/index.md) |

## Lancer cette doc

```bash
cd docs
docker compose up      # http://localhost:8000
```
