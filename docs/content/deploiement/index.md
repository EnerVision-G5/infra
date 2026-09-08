# Déploiement

Deux playbooks, joués dans cet ordre :

| Playbook | Cible | Ce qu'il fait |
|---|---|---|
| `provision.yml` | `all` | réseaux Docker partagés → Traefik → Garage → PostgreSQL → Kafka → MLflow → monitoring |
| `deploy.yml` | `application_servers` | rôle `applications` : front, api, collector |

## Pourquoi cet ordre

`deploy.yml` suppose que les réseaux Docker, Traefik, PostgreSQL et Kafka
existent déjà : l'API se raccroche à `proxy_network` / `db_network`, le
`collector` pousse dans `kafka` sur `broker_network`. `provision.yml` d'abord,
donc.

La base est déployée **vide** par `provision.yml`. C'est l'entrypoint du
conteneur `api` (dans `deploy.yml`) qui applique le schéma via
`alembic upgrade head` — voir [Services › PostgreSQL](../services/postgres.md).

## Prérequis

Sur le poste de contrôle :

| | |
|---|---|
| `ansible-core`, `ansible-lint` | `pip install ansible-core ansible-lint` |
| collections | `ansible-galaxy collection install -r ansible/requirements.yml` |
| **`sshpass`** | l'inventaire se connecte en mot de passe — obligatoire |
| mot de passe du Vault | `--ask-vault-pass`, `--vault-password-file`, ou `ANSIBLE_VAULT_PASSWORD_FILE` |
| Vault renseigné | tous les `vault_*` requis (voir [Secrets](../secrets/index.md)) |
| DNS | les domaines `*.enervision.com` doivent résoudre vers la VM |
| accès GHCR | le rôle `applications` fait `docker login ghcr.io` avec `ghcr_username` / `ghcr_token` (Vault) |

## Commandes

```bash
# Provisionnement (réseaux Docker + Traefik + Garage + PostgreSQL + Kafka + MLflow + monitoring)
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass

# Déploiement applicatif
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass
```

## Rejouer un rôle seul

`provision.yml` porte des tags :

```bash
ansible-playbook ansible/playbooks/provision.yml --tags traefik      --ask-vault-pass
ansible-playbook ansible/playbooks/provision.yml --tags garage       --ask-vault-pass
ansible-playbook ansible/playbooks/provision.yml --tags postgres     --ask-vault-pass   # ou --tags database
ansible-playbook ansible/playbooks/provision.yml --tags kafka        --ask-vault-pass
ansible-playbook ansible/playbooks/provision.yml --tags mlflow       --ask-vault-pass
ansible-playbook ansible/playbooks/provision.yml --tags monitoring   --ask-vault-pass
```

La création des réseaux Docker est taguée `always` : elle tourne même avec
un `--tags` ciblé.

## Suite

- [provision.yml](provision.md)
- [deploy.yml](applications.md) — mise à jour d'une version
- [Intégration continue de ce dépôt](ci-infra.md)
- [Premier déploiement (VM neuve)](premier-deploiement.md)
