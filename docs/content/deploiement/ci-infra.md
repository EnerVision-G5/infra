# Intégration continue de ce dépôt

`.github/workflows/ci.yml` — ce qui est vérifié sur **chaque pull request**
du dépôt infra.

!!! info "Hors périmètre"
    La construction et la publication des **images applicatives** (front,
    api, predict) sont pilotées par les pipelines de **leurs propres
    dépôts**. Côté infra, on ne fait que *consommer* les images GHCR en les
    épinglant par SHA — voir [deploy.yml](applications.md).

## Déclenchement

`on: pull_request` **uniquement**. Un push direct sur une branche n'est pas
testé : le passage par une PR est la seule voie contrôlée.

## Job `ansible`

| Étape | Commande |
|---|---|
| collections | `ansible-galaxy collection install -r ansible/requirements.yml` |
| syntaxe | `ansible-playbook --syntax-check` sur `provision.yml` **et** `deploy.yml` |
| lint | `ansible-lint ansible/` |

Le mot de passe du Vault est optionnel : s'il est fourni via le secret GitHub
`ANSIBLE_VAULT_PASSWORD`, il est écrit hors dépôt le temps du job (lève les
avertissements de déchiffrement) ; sinon la validation passe quand même.

## Job `secrets`

| Étape | Détail |
|---|---|
| checkout | `fetch-depth: 0` — l'historique complet, pour scanner les commits passés |
| gitleaks | version `8.21.2`, installée dans le job |
| `bash scripts/check-secrets.sh` | Vault chiffré + variables sensibles en indirection + placeholders + `gitleaks detect` (arbre **et** historique) |

Détail de ce que teste `check-secrets.sh` :
[Secrets › Vérification](../secrets/verification.md).

## Rejouer en local

```bash
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml

ansible-playbook --syntax-check ansible/playbooks/provision.yml
ansible-playbook --syntax-check ansible/playbooks/deploy.yml
ansible-lint ansible/
bash scripts/check-secrets.sh          # installe gitleaks si tu veux le scan complet
```

## La doc

La documentation MkDocs n'est **pas** encore dans la CI. Contrôle manuel :

```bash
cd docs
docker compose run --rm --user "$(id -u):$(id -g)" docs build --strict
```

`--strict` échoue sur un lien mort, une référence cassée ou une navigation
invalide.
