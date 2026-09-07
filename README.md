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

Ce dépôt n'est pas un service applicatif : aucun endpoint. La CI ne fait que
valider ; l'hôte est configuré et les applications déployées par
`ansible-playbook`, lancé depuis un poste de l'équipe (voir
[Déployer](#déployer)).

Le dossier [`terraform/`](terraform/README.md) est le pendant cloud, ouvert
avec un POC : un compte de stockage Blob Azure pour l'environnement `POC`
dans le groupe de ressources fourni par l'école, état distant, CI/CD dédiée
(`terraform.yml`, plan sur PR, apply à la fusion, OIDC sans secret). Il ne
change rien à la cible on-premise.

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

`.github/workflows/terraform.yml` ne se déclenche que si `terraform/` change :
`fmt`, `validate`, `tflint` et `plan` commenté sur la PR, par environnement ;
`apply` au push sur `develop` (`master` pour `PROD`). Détail dans
[terraform/README.md](terraform/README.md#cicd).

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

Prérequis sur le poste qui déploie :

- `ansible-core` et les collections (`ansible-galaxy collection install -r
  ansible/requirements.yml`) ;
- `sshpass`, tant que l'hôte est joint par mot de passe (cf. `hosts.yml`) ;
- une route vers la VM (réseau de l'école ou VPN) : aucun runner GitHub n'y
  accède, voir [Déployer depuis GitHub Actions](#déployer-depuis-github-actions) ;
- le mot de passe du Vault.

### Provisionner l'hôte

```bash
# Réseaux Docker partagés + Traefik, Garage, TimescaleDB, monitoring
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass
```

Un rôle seul peut être rejoué via ses tags :

```bash
ansible-playbook ansible/playbooks/provision.yml --tags monitoring --ask-vault-pass
```

### Mettre en production une version

Il n'y a pas de déploiement automatique. La chaîne complète est :

1. un merge sur `master` du dépôt de service déclenche son workflow CD, qui
   rejoue la CI, construit l'image et la publie sur GHCR sous le tag
   `sha-<sha git complet>` ;
2. quelqu'un reporte ce tag dans `applications_<app>_sha`
   (`ansible/inventories/on-premise/group_vars/all/vars.yml`) par une PR sur
   `develop` ;
3. une fois la PR fusionnée, `ansible-playbook deploy.yml` est lancé depuis un
   poste ;
4. la version est vérifiée sur l'hôte et depuis un navigateur.

La PR de bump est ce qui rend le déploiement traçable : `vars.yml` sur
`develop` **est** l'état attendu de la production. Un SHA poussé sans PR ou un
`compose.yml` retouché à la main sur l'hôte casse cette équivalence, et le
prochain passage du playbook écrase de toute façon la retouche.

| Variable de `vars.yml`     | Image GHCR (`ghcr.io/enervision-g5/…`) | Dépôt       | Workflow CD         |
| -------------------------- | -------------------------------------- | ----------- | ------------------- |
| `applications_front_sha`   | `dashboard`                            | `dashboard` | `cd.yml`            |
| `applications_api_sha`     | `api`                                  | `api`       | `cd.yml`            |
| `applications_serving_sha` | `predict/serving`                      | `predict`   | `cd-serving.yml`    |
| `applications_training_sha`| `predict/training`                     | `predict`   | `cd-training.yml`   |
| `applications_etl_sha`     | `predict/etl`                          | `predict`   | `cd-etl.yml`        |
| `applications_collector_sha` | `predict/collector`                  | `predict`   | `cd-collector.yml`  |

`mlflow` tourne sur l'image `predict/training` et `predict-cron` sur l'image
`api` : ils suivent `applications_training_sha` et `applications_api_sha`, sans
variable propre.

#### 1. Lire le SHA publié

Deux sources, à recouper :

- **Le run CD** : onglet *Actions* du dépôt de service, workflow `cd` (ou
  `cd-<service>` pour `predict`) sur `master`, job « Build & push image
  (GHCR) ». Son résumé « Image publiée » liste les tags poussés, dont
  `ghcr.io/enervision-g5/<image>:sha-<sha>`. En ligne de commande :

  ```bash
  gh run list -R EnerVision-G5/api --workflow cd.yml --branch master -L 5 \
    --json headSha,conclusion,url
  ```

  Le tag à déployer est `sha-<headSha>` du dernier run **`success`**.

- **La page Packages du dépôt** (*Code → Packages*, par exemple
  `https://github.com/EnerVision-G5/dashboard/pkgs/container/dashboard`, ou
  `…/predict/pkgs/container/predict%2Fserving` pour les images de `predict`).
  Chaque version y apparaît avec ses tags et sa date de publication.

Ce que la page Packages ne dit pas : le workflow **pousse l'image avant de la
tester**. Un run rouge à l'étape « Smoke test de l'image publiée » laisse donc
sur GHCR un tag qui n'a pas été validé. Vérifier le run, pas seulement la
présence du tag. Trois autres pièges :

- le tag `latest` est déplacé à chaque publication : ne jamais le déployer,
  le rôle exige un `sha-…` et refuse une valeur vide ;
- les quatre workflows de `predict` ne se déclenchent que sur les fichiers de
  leur service : un commit qui ne touche que `services/etl` ne publie que
  `predict/etl`, les trois autres images gardent leur tag précédent. Aligner
  les quatre variables sur un même SHA suppose que les quatre runs ont eu lieu ;
- le SHA est celui du **commit de merge sur `master`**, pas celui du dernier
  commit de la branche de travail.

#### 2. Ouvrir la PR de bump

```bash
git fetch origin develop
git switch -c deploy-api-<sha court> origin/develop
$EDITOR ansible/inventories/on-premise/group_vars/all/vars.yml   # applications_api_sha
git commit -am "Déployer api sha-<sha court>"
git push -u origin HEAD
gh pr create --base develop --fill
```

Dans la description, coller le lien du run CD dont provient le SHA : c'est la
preuve que l'image a passé la CI du service. La CI d'`infra` vérifie la
syntaxe, `ansible-lint` et l'absence de secret ; le rôle `applications`
contrôlera au déploiement que chaque application a un SHA et qu'aucun couple
image:tag n'est dupliqué. Fusionner après relecture, puis :

```bash
git switch develop && git pull --ff-only origin develop
```

#### 3. Déployer

```bash
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass
```

Le rôle écrit le SHA attendu dans `/opt/srv/applications/<app>/.sha`. Seules
les applications dont ce fichier change voient leur image tirée depuis GHCR et
leur conteneur recréé ; les autres ressortent en `ok`. Un second passage sans
changement de version doit donc se terminer avec `changed=0` sur les tâches
d'image et de compose : c'est aussi le moyen de vérifier que l'hôte est bien
dans l'état décrit par Git.

Les traitements datés (`training`) ne sont pas démarrés par le déploiement : leur
image est tirée, leur prochain lancement par timer systemd utilisera la nouvelle
version.

#### 4. Vérifier

Depuis un poste qui résout les domaines de `vars.yml` (le schéma suit
`traefik_entrypoint`, `http` aujourd'hui) :

```bash
curl -fsS http://app.enervision.com/healthz
curl -fsS http://api.enervision.com/api/v1/health
```

Sur l'hôte, pour l'image réellement en service et l'état des sondes, y compris
les services qui n'ont pas de route publique :

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker inspect -f '{{.State.Health.Status}}' enervision-api enervision-serving
docker logs --since 10m enervision-api
```

`docker ps` doit afficher le tag de `vars.yml` et `(healthy)` pour chaque
conteneur qui porte une sonde. Terminer par un parcours dans le dashboard :
connexion, choix d'un site, affichage des mesures et de la prédiction.

#### 5. Revenir en arrière

Le retour arrière est un déploiement comme un autre, avec le SHA précédent. Il
suit la même PR, ce qui garde `develop` fidèle à l'hôte :

```bash
git log --oneline -- ansible/inventories/on-premise/group_vars/all/vars.yml
git switch -c rollback-api origin/develop
git revert <commit de bump>          # ou remettre l'ancien SHA à la main
git push -u origin HEAD && gh pr create --base develop --fill
```

En urgence, déployer depuis cette branche sans attendre la relecture
(`ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass` depuis la
branche `rollback-api`), puis faire fusionner la PR dans la foulée : la
production ne doit pas rester sur une version absente de `develop`. Ne jamais
corriger `compose.yml` ou `.env` directement sur l'hôte, le playbook les
regénère.

Ce que le retour d'image ne défait pas :

- **le schéma de la base.** L'API applique `alembic upgrade head` à son
  démarrage ; revenir à une image antérieure ne rejoue pas les migrations à
  l'envers. Une ancienne API fonctionne sur un schéma plus récent tant que la
  migration n'a fait qu'ajouter ; si elle a renommé ou supprimé, le retour
  arrière passe par `alembic downgrade` depuis le dépôt `api`, avant de
  redéployer ;
- **le modèle servi.** `serving` résout l'alias `champion` dans le registre
  MLflow au démarrage. Revenir sur un mauvais modèle se fait dans le registre,
  en redonnant l'alias à la version précédente puis en redémarrant `serving`,
  pas en changeant d'image ;
- **les données écrites** entre-temps (mesures, prédictions archivées) : elles
  restent, c'est voulu.

### Déployer depuis GitHub Actions

La checklist de projet attend un déploiement « par le pipeline, sans commande
manuelle ». Sur la VM on-premise, ce n'est pas possible tel quel : elle est
sur un réseau privé (`10.105.200.0/24`), les runners hébergés par GitHub ne
peuvent pas la joindre. La seule voie serait un **runner auto-hébergé**
installé sur la VM (ou une machine du même réseau), qui interroge GitHub en
sortie HTTPS et exécuterait un workflow `workflow_dispatch` lançant
`ansible-playbook` en local.

Ce que ça coûterait et ce que ça rapporterait, au vu de l'état actuel :

| | |
| --- | --- |
| **Faisabilité** | Oui. Installation en une vingtaine de minutes (archive du runner, `config.sh` avec un jeton d'enregistrement du dépôt `infra`, service systemd). Aucun coût : les runners auto-hébergés sont gratuits sur un dépôt privé du plan gratuit. Le runner a besoin de Docker, donc d'un accès équivalent à root sur l'hôte de production. |
| **Gain réel** | Le journal du déploiement est sur GitHub, le mot de passe du Vault n'existe qu'en secret Actions au lieu d'être sur quatre postes, plus besoin d'Ansible ni d'un accès au réseau de l'école pour déployer. Sur la traçabilité, l'essentiel est déjà obtenu par la PR de bump : la version déployée est celle de `vars.yml`. |
| **Ce qui manque pour le faire sûrement** | Sur un dépôt privé du plan gratuit, GitHub n'offre ni protection de branche (l'API répond « Upgrade to GitHub Pro »), ni règles de protection d'environnement (relecteur obligatoire), ni groupes de runners réservés à certains workflows. Concrètement : toute personne avec le droit d'écriture peut pousser une branche dont un workflow indique `runs-on: self-hosted` et l'exécuter, sans relecture, avec les droits du runner sur l'hôte de production. |
| **Ordre des chantiers** | L'hôte est encore joint en root par mot de passe et servi en HTTP clair. Ajouter un agent permanent avec accès Docker sur cette machine avant d'avoir corrigé ces deux points ajoute une surface d'attaque au mauvais moment. |
| **Cadence** | Quatre personnes, quelques mises en production par jour au plus, un seul environnement. La commande manuelle prend deux minutes une fois la PR fusionnée. |

**Décision : pas de runner auto-hébergé pour l'instant.** La mise en production
reste manuelle, tracée par la PR de bump décrite ci-dessus. À réexaminer si
l'une de ces conditions change : durcissement SSH et TLS terminés ; passage à
un plan GitHub (ou dépôt public) donnant les environnements avec relecteur
obligatoire et les groupes de runners ; cadence ou nombre d'environnements
rendant la commande manuelle pénible.

Si le sujet est rouvert, le montage minimal est : runner installé par Ansible
sur la VM sous un utilisateur dédié membre du groupe `docker`, enregistré sur le
seul dépôt `infra`, workflow en `workflow_dispatch` uniquement avec
`concurrency` pour sérialiser les déploiements, `ansible_connection: local`,
mot de passe du Vault en secret Actions.

Un pas intermédiaire, sans runner, apporterait déjà quelque chose : un job CI
sur les PR d'`infra` qui vérifie que chaque `applications_*_sha` existe sur
GHCR (`docker manifest inspect`). Il demande un jeton en lecture sur les
paquets des trois dépôts de service et arrêterait un SHA mal copié avant qu'il
n'atteigne l'hôte.

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
