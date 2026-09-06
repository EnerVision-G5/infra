# CI / CD

Ce qui est automatisé, et ce qui reste manuel.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- CI infra : ansible-lint, syntax-check, check-secrets + gitleaks
- CD des dépôts api / front / predict : build image → GHCR, tag sha-<git>
- Ce qui n'est PAS automatisé : le déploiement sur la VM (ansible à la main)
- Récupérer le SHA d'image à déployer
