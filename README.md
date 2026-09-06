# infra

[![ci](https://github.com/EnerVision-G5/infra/actions/workflows/ci.yml/badge.svg)](https://github.com/EnerVision-G5/infra/actions/workflows/ci.yml)

Infrastructure as Code du projet EnerVision. Depuis la décision d'architecture
V2, la plateforme est **intégralement on-premise**, en conteneurs Docker
Compose derrière Traefik, déployée par **Ansible**. Terraform et les ressources
Azure sont sortis du périmètre.

La VM de l'école est fournie **déjà provisionnée** (Docker installé et
configuré, GPU, durcissement système) : Ansible ne fait plus que déployer les
stacks dessus, il ne touche ni aux paquets, ni à SSH, ni au pare-feu, ni à
`/etc/docker/daemon.json`.

Ce dépôt n'est pas un service applicatif : aucun endpoint, tout est exécuté par
le pipeline ou par un `ansible-playbook`.

## Périmètre

`provision.yml` crée d'abord les réseaux Docker partagés (`docker_external_networks`),
puis applique :

| Rôle Ansible  | Ce qu'il installe                                              |
| ------------- | -------------------------------------------------------------- |
| `traefik`     | Point d'entrée unique, TLS, routage                             |
| `garage`      | Stockage objet compatible S3 (artefacts, archives)             |
| `timescaledb` | PostgreSQL + TimescaleDB — le **schéma** est porté par les migrations Alembic du dépôt `api`, jamais ici |
| `monitoring`  | Prometheus, Grafana, Loki + Promtail, node_exporter, cAdvisor   |

`deploy.yml` applique le rôle `applications` : Front / API / Predict, un
`compose.yml` par service, images GHCR épinglées par SHA.

## CI

`.github/workflows/ci.yml` s'exécute à chaque push et sur chaque pull request :

| Étape      | Commande                                                 |
| ---------- | -------------------------------------------------------- |
| Collections | `ansible-galaxy collection install -r ansible/requirements.yml` |
| Syntaxe    | `ansible-playbook --syntax-check` sur `provision.yml` et `deploy.yml` |
| Lint       | `ansible-lint ansible/`                                   |
| Secrets    | `scripts/check-secrets.sh` + `gitleaks detect` (job `secrets`) |

Un playbook invalide, un rôle non conforme ou un secret en clair fait échouer
la PR.

## Développer en local

```bash
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml
ansible-lint ansible/
ansible-playbook --syntax-check ansible/playbooks/provision.yml
ansible-playbook --syntax-check ansible/playbooks/deploy.yml
bash scripts/check-secrets.sh
```

## Déployer

L'inventaire cible la VM on-premise
(`ansible/inventories/on-premise/hosts.yml`). Les deux playbooks lisent le Vault
chiffré : ajouter `--ask-vault-pass` (ou `--vault-password-file`, voir
[Secrets](#secrets)).

```bash
# Réseaux Docker partagés + Traefik, Garage, TimescaleDB, monitoring
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass

# Déploiement applicatif (Front / API / Predict)
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass
```

Un rôle seul peut être rejoué via ses tags :

```bash
ansible-playbook ansible/playbooks/provision.yml --tags monitoring --ask-vault-pass
```

### Configuration applicative

Chaque application reçoit son `.env`, rendu depuis `<nom>.env.j2` et monté par
`env_file` dans son `compose.yml`. Aucune application ne lit sa configuration
au build : les images sont épinglées par SHA et déployées telles quelles sur
des environnements dont les domaines diffèrent.

Deux réglages doivent **concorder**, sinon le navigateur bloque les appels du
dashboard vers l'API malgré une configuration correcte d'un seul côté :

| Variable | Application | Rôle |
| --- | --- | --- |
| `applications_front_csp_connect_src` | front | Autorise le navigateur à **émettre** l'appel (directive `connect-src` de la CSP) |
| `applications_api_cors_allowed_origins` | api | Autorise le navigateur à **lire** la réponse (CORS) |

Les deux dérivent de `applications_front_host` et `applications_api_host` :
surcharger un domaine dans `group_vars` les emmène toutes les deux, sans écrire
d'adresse en double. Le rôle refuse une valeur vide ou contenant un joker, pour
l'une comme pour l'autre.

Leur **schéma** dérive de `traefik_entrypoint`, il n'est jamais écrit en dur :

| `traefik_entrypoint` | `applications_public_scheme` |
| --- | --- |
| `web` (port 80, valeur actuelle) | `http` |
| `websecure` (port 443) | `https` |

Ce n'est pas un détail cosmétique. Pour un navigateur, `http://app…` et
`https://app…` sont deux **origines différentes** : annoncer l'une pendant que
Traefik sert l'autre fait échouer le CORS et la CSP ensemble, avec un message
de blocage cross-origin qui ne dit pas que seul le schéma cloche. Le jour où
l'on bascule sur `websecure` — et où l'on décommente les labels TLS des
routeurs applicatifs — les origines suivent d'elles-mêmes.

Ces valeurs ne sont pas des secrets — ce sont des adresses de service, que le
dashboard republie d'ailleurs en clair sur `/config.js`. **Rien de sensible ne
doit passer par la configuration du front.**

## Secrets

Il n'y a plus de Key Vault. Tous les mots de passe, tokens et identifiants
sensibles sont regroupés dans un **fichier Vault chiffré, versionné** :

```
ansible/inventories/on-premise/group_vars/all/
├── vars.yml    # variables non sensibles + rattachement clef -> vault_*
└── vault.yml   # chiffré avec ansible-vault ($ANSIBLE_VAULT en tête)
```

Les rôles et templates ne référencent que les variables « métier »
(`ghcr_token`, `timescaledb_password`, …) ; `vars.yml` les fait pointer vers les
`vault_*` définis dans `vault.yml`. Aucune valeur sensible n'apparaît en clair
dans le dépôt.

| Variable métier (rôles / templates)  | Clé Vault (`vault.yml`)                   | Utilisée par |
| ------------------------------------ | ---------------------------------------- | ------------ |
| `garage_rpc_secret`                  | `vault_garage_rpc_secret`                | `garage`     |
| `garage_admin_token`                 | `vault_garage_admin_token`              | `garage`     |
| `garage_metrics_token`               | `vault_garage_metrics_token`            | `garage`     |
| `timescaledb_password`               | `vault_timescaledb_password`            | `timescaledb`, `applications` |
| `ghcr_username`                      | `vault_ghcr_username`                   | `applications` |
| `ghcr_token`                         | `vault_ghcr_token`                      | `applications` |
| `monitoring_grafana_admin_password`  | `vault_monitoring_grafana_admin_password` | `monitoring` |
| `applications_api_jwt_secret`        | `vault_applications_api_secret_key`     | `applications` |
| `ansible_password`                   | `vault_ansible_ssh_password`            | connexion SSH à l'hôte (`hosts.yml`) |

Pour ajouter un secret : le déclarer dans `vault.yml` sous `vault_<nom>`
(`ansible-vault edit`), puis ajouter la ligne `<nom>: "{{ vault_<nom> }}"` dans
`vars.yml` et l'entrée correspondante dans `scripts/check-secrets.sh`
(`secret_vars`).

### Mot de passe du Vault

Le mot de passe **n'est jamais commité**. Trois options :

```bash
# 1. interactif
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass

# 2. fichier local hors Git (couvert par .gitignore : .vault_pass*)
echo 'mon-mot-de-passe' > .vault_pass && chmod 600 .vault_pass
ansible-playbook ansible/playbooks/deploy.yml --vault-password-file .vault_pass

# 3. variable d'environnement
export ANSIBLE_VAULT_PASSWORD_FILE=~/.config/enervision/vault-pass
```

En CI, le mot de passe est lu depuis le secret GitHub Actions
`ANSIBLE_VAULT_PASSWORD` (**Settings → Secrets and variables → Actions**). Y
placer `changeme` tant que le Vault n'a pas été roté, puis la nouvelle valeur
après `ansible-vault rekey`. S'il est absent, `--syntax-check` et `ansible-lint`
passent quand même (avec un avertissement de déchiffrement) ; seul un futur job
qui exécute réellement un playbook en aurait besoin.

### Éditer / roter

```bash
ansible-vault edit  ansible/inventories/on-premise/group_vars/all/vault.yml
ansible-vault rekey  ansible/inventories/on-premise/group_vars/all/vault.yml
```

> Le `vault.yml` versionné ne contient que des placeholders d'amorçage
> (`REMPLACER_*`), chiffrés avec le mot de passe `changeme`. **Avant tout
> déploiement réel** : `ansible-vault rekey`, puis `ansible-vault edit` pour
> renseigner les vrais secrets.

### Vérification

`scripts/check-secrets.sh` (job CI `secrets`) vérifie que `vault.yml` est
chiffré, qu'aucune variable sensible n'est définie en clair et qu'aucun
placeholder ne subsiste ; `gitleaks` scanne l'arbre **et l'historique** Git.

Les fuites historiques déjà connues et traitées sont listées dans
`.gitleaksignore`. **Un secret présent dans l'historique est compromis** : le
roter sur l'hôte, pas seulement le retirer de l'arbre.
