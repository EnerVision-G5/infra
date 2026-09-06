# Intégration continue de ce dépôt

Ce que la CI vérifie sur une PR **du dépôt infra**, et comment rejouer ces
contrôles en local.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Le workflow `.github/workflows/ci.yml` : `ansible-lint`, `--syntax-check`
  (provision + deploy), `check-secrets.sh` + `gitleaks`
- Rejouer les mêmes contrôles en local
- Le flux : tout passe par une PR, un push direct n'est pas testé

!!! info "Hors périmètre"
    La construction et la publication des **images applicatives** (front,
    api, predict) sont pilotées par les pipelines de **leurs propres
    dépôts** et documentées là-bas. Côté infra, on ne fait que *consommer*
    les images publiées sur GHCR, en les épinglant par SHA — voir
    [deploy.yml](applications.md).
