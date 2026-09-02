# infra

[![ci](https://github.com/EnerVision-G5/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/EnerVision-G5/infra/actions/workflows/ci.yml)

Infrastructure as Code du projet EnerVision. Depuis la décision d'architecture
V2, la plateforme est **intégralement on-premise** : tout est provisionné et
configuré par **Ansible** sur la VM de l'école, en conteneurs Docker Compose,
derrière Traefik. Terraform et les ressources Azure sont sortis du périmètre.

Ce dépôt n'est pas un service applicatif : aucun endpoint, tout est exécuté par
le pipeline ou par un `ansible-playbook`.

## Périmètre

| Rôle Ansible  | Ce qu'il installe                                              |
| ------------- | -------------------------------------------------------------- |
| `base`        | Paquets système de base                                         |
| `ssh`         | Durcissement SSH (port dédié, clés uniquement)                  |
| `firewall`    | UFW, ouverture des seuls ports nécessaires                      |
| `security`    | Mises à jour de sécurité automatiques                           |
| `docker_engine` | Docker Engine, Compose et les réseaux externes du projet      |
| `traefik`     | Point d'entrée unique :443, TLS, routage                        |
| `garage`      | Stockage objet compatible S3 (artefacts, archives)              |
| `timescaledb` | PostgreSQL + TimescaleDB                                        |
| `monitoring`  | Prometheus, Grafana, Loki + Promtail, node_exporter, cAdvisor   |
| `applications` | Déploiement Front / API / Predict — un `compose.yml` par application, images GHCR épinglées par SHA |

## CI

`.github/workflows/ci.yml` s'exécute à chaque push et sur chaque pull request :

| Étape      | Commande                                                 |
| ---------- | -------------------------------------------------------- |
| Collections | `ansible-galaxy collection install -r ansible/requirements.yml` |
| Syntaxe    | `ansible-playbook --syntax-check ansible/playbooks/provision.yml` |
| Lint       | `ansible-lint ansible/`                                   |

Un playbook invalide ou un rôle non conforme fait échouer la PR.

## Développer en local

```bash
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml
ansible-lint ansible/
ansible-playbook --syntax-check ansible/playbooks/provision.yml
```

## Déployer

L'inventaire cible la VM on-premise
(`ansible/inventories/on-premise/hosts.yml`).

```bash
ansible-playbook ansible/playbooks/provision.yml
```

Un rôle seul peut être rejoué via ses tags :

```bash
ansible-playbook ansible/playbooks/provision.yml --tags monitoring
```

## Secrets

Il n'y a plus de Key Vault : les secrets sont portés par des variables Ansible
chiffrées avec `ansible-vault` et rendus sur la VM sous forme de fichiers `.env`
hors Git. Les secrets nécessaires à la CI restent dans les secrets GitHub
Actions. Aucun secret en clair ne doit être commité.
