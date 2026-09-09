# terraform

Infrastructure Azure d'EnerVision. Périmètre actuel : du **stockage Blob**
pour `DEV` et `PROD`, un conteneur par environnement sur le compte du
projet. Rien ici ne touche la VM on-premise, qui reste sous
[Ansible](../ansible/) ; ce dossier est le pendant cloud, avec la même
logique.

## Logique

| Ansible | Terraform | Rôle |
| --- | --- | --- |
| `roles/` | `modules/tf-module-enervision/` | Décrit les briques du projet, un fichier par brique, sans savoir où elles atterrissent |
| `inventories/<cible>` | `<ENV>/` | Dit ce qui existe pour une cible : un appel du module projet avec ses valeurs, son abonnement, son groupe de ressources |
| Vault chiffré | Aucun secret dans le code | L'accès passe par une identité (session `az login`, OIDC en CI) et des rôles, jamais par une clé |
| L'hôte est la vérité | L'état (`<ENV>.tfstate`) est la vérité | Distant, verrouillé, versionné ; jamais en local, jamais dans Git |

```
terraform/
├── DEV/                        un dossier par environnement (MAJUSCULES)
│   ├── .terraform-version      version de Terraform, lue par tfenv et par la CI
│   ├── .terraform.lock.hcl     versions des fournisseurs, verrouillées
│   ├── DEV.auto.tfvars         valeurs de l'environnement : abonnement, groupe, équipe, briques
│   ├── DEV.backend.tf          où vit l'état : compte du projet, clé DEV.tfstate
│   ├── providers.tf            versions, fournisseur (sans identifiant)
│   ├── main.tf                 un appel du module projet, avec les valeurs de l'environnement
│   ├── variables.tf / outputs.tf
├── PROD/                       même structure, appliqué depuis master
├── modules/
│   └── tf-module-enervision/   le projet : fichiers communs + un fichier par brique
│       ├── main.tf             groupe de ressources (fourni), noms, étiquettes
│       ├── variables.tf        commun, puis une section par brique
│       ├── outputs.tf
│       ├── storage.tf          conteneurs de l'environnement sur le compte du projet
│       ├── iam.tf              droits : équipe, identités applicatives, au conteneur
│       └── workload_identity.tf  identités des API on-premise (fédération, émetteur à nous)
├── scripts/
│   ├── bootstrap.sh            une fois : compte du projet, identité CI
│   ├── allow-ci.sh             ouvrir un autre groupe de ressources à la chaîne
│   ├── new-env.sh              nouvel environnement à partir d'un existant
│   ├── issuer-keygen.sh        paire de clés de l'émetteur d'un environnement
│   ├── workload-token.sh       jeton de test pour une identité applicative
│   └── blob-demo.py            démonstration Python : jeton, échange, lecture/écriture
├── docs/
│   ├── organisation-azure.md   ce que l'école donne et interdit, l'équipe, les droits
│   └── identites-applicatives.md  brancher une API Python sur les blobs, sans secret
└── .tflint.hcl
```

Deux règles :

- **Un module projet, un dossier par environnement.** `DEV/main.tf` ne
  contient qu'un appel du module avec ses valeurs. Ajouter une brique au
  projet, c'est un fichier de plus dans le module (et ses variables, dans
  la section du même nom de `variables.tf`) ; ajouter un environnement,
  c'est copier un dossier. Tous les environnements portent les mêmes
  briques, réglées différemment.
- **Le groupe de ressources est fourni, et c'est la frontière.** L'école
  en donne un par étudiant, sans droit d'en créer d'autres ; Terraform y
  crée tout et ne peut rien toucher ailleurs, l'identité CI non plus.
  Deux gestes restent humains, et c'est voulu : le bootstrap, une fois
  par groupe, et le clic qui applique.

## En pratique

| Je veux… | Je fais… | Qui applique |
| --- | --- | --- |
| Changer quelque chose (une brique, une valeur) | Une branche, une PR : le plan arrive en commentaire, relu avec le code | Après fusion, *Actions → terraform → Run workflow*, branche `develop` (`master` pour `PROD`), environnement saisi |
| Déployer ce qui est fusionné | Rien à coder | Le même lancement manuel. **Rien ne s'applique tout seul**, ni à la fusion ni au push |
| Ajouter un environnement | *Actions → terraform-new-env → Run workflow* (ou `scripts/new-env.sh`) : le dossier est créé et sa PR ouverte ; relire son `.auto.tfvars` | Lancement manuel après fusion |
| Mettre un environnement dans un autre groupe de ressources (rare) | Celui qui tient le groupe lance `scripts/allow-ci.sh` dessus, puis le groupe va dans `<ENV>.auto.tfvars` par PR | idem |
| Ajouter quelqu'un, changer son niveau, le retirer | Une ligne dans `team` du `<ENV>.auto.tfvars`, par PR | idem |
| Ajouter une brique au projet | Un fichier dans `modules/tf-module-enervision/`, ses variables dans `variables.tf`, ses valeurs dans chaque `<ENV>.auto.tfvars` | idem, environnement par environnement |
| Donner l'accès aux blobs à une API on-premise | `scripts/issuer-keygen.sh <ENV>` une fois (clé privée au vault Ansible, clé publique dans le tfvars), niveaux dans `blob_workloads`, PR ; puis `terraform output workload_identities` pour le `.env` de l'API. Détail : [docs/identites-applicatives.md](docs/identites-applicatives.md) | idem |
| Voir ce qui est déployé | `terraform plan` en local (niveau `devops`), ou le portail Azure | — |
| Démarrer sur un nouvel abonnement ou un premier groupe | `scripts/bootstrap.sh <groupe>`, une fois | — |

## Configuration

Le fournisseur ne lit **aucun identifiant dans le code** :

| Quoi | Où | En local | En CI |
| --- | --- | --- | --- |
| Abonnement, groupe de ressources | `<ENV>.auto.tfvars` et `<ENV>.backend.tf`, écrits par le bootstrap pour le premier environnement, recopiés pour les suivants | idem | idem |
| Identité | — | la session `az login` | `ARM_CLIENT_ID` + `ARM_TENANT_ID` + `ARM_USE_OIDC=true`, depuis les secrets `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` |
| Accès à l'état | `use_azuread_auth = true` | votre rôle *Storage Blob Data Contributor* sur le groupe | rôle de l'identité CI |

Ce que le groupe de l'école impose, et que le module respecte : région
`francecentral` seule, étiquette `user` égale à celle du groupe sur chaque
ressource, comptes de stockage en `Standard_LRS`, et **deux comptes de
stockage au plus** par groupe, compteur tenu par une automatisation de
l'école qui refuse ensuite toute création ou modification. D'où **un seul
compte pour le projet**, créé par le bootstrap : il porte l'état Terraform
et un conteneur par environnement et par usage (`dev-data`, `prod-data`).
La séparation entre environnements se fait au conteneur, droits compris :
un `member` de `PROD` ne lit pas les blobs de `DEV`. Le détail des droits
et des interdits : [docs/organisation-azure.md](docs/organisation-azure.md).

Conventions, celles du
[Cloud Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) :
`st<projet>tf<suffixe>` pour le compte du projet (ni tiret ni majuscule,
unique au monde : suffixe tiré de l'abonnement), `<env>-<usage>` pour les
conteneurs, `id-<projet>-github`. Étiquettes partout : `project`,
`environment`, `managed_by`, `repository`, `user`.

## Démarrer (une fois, celui qui tient le groupe)

```bash
bash terraform/scripts/bootstrap.sh rg-MCharge2024_cours-projet-eadl
```

Le script crée le compte de stockage du projet (état + conteneurs, sans
clé partagée, versions, corbeille), l'identité managée de la CI avec ses
identifiants fédérés GitHub et les mêmes rôles que vous sur le groupe,
pousse les deux secrets GitHub, et écrit abonnement, groupe et compte dans
les `<ENV>.auto.tfvars` et `<ENV>.backend.tf`.

## L'équipe

Même logique qu'un projet GCP : le groupe de ressources est le projet, les
gens s'y voient donner un niveau, et se connectent avec leur propre compte
(campus) pour le voir dans le portail. Deux niveaux, dans `team` du
`<ENV>.auto.tfvars` de chaque environnement (la production n'a pas
forcément les mêmes `devops` que le développement) :

| Niveau | Comme sur GCP | Sur le groupe (commun) | Sur les blobs (de cet environnement seul) |
| --- | --- | --- | --- |
| `member` | viewer | `Reader` : voit tout | `Storage Blob Data Reader` sur les conteneurs de l'environnement |
| `devops` | editor | `Reader`, `Devops-cours-projet-eadl` (le rôle de l'école, celui que vous tenez) : crée, modifie | `Storage Blob Data Contributor` sur les conteneurs de l'environnement et sur `tfstate` (pour `terraform plan` en local) |

Une entrée par personne, clé = courriel, avec son objectId Entra ID (le
courriel peut changer, l'identifiant non, et la CI n'a pas le droit
d'interroger l'annuaire) :

```bash
az ad user show --id prenom.nom@campus-eni.fr --query id -o tsv
```

```hcl
team = {
  "prenom.nom@campus-eni.fr" = { role = "devops", object_id = "…" }
  "autre.nom@campus-eni.fr"  = { role = "member", object_id = "…" }
}
```

Les rôles sur le groupe et l'accès à `tfstate` sont **par groupe de
ressources**, pas par environnement : un seul environnement du groupe les
pose, celui du bootstrap (`project_roles = true` dans `DEV`). La liste
`team` de `PROD` ne décide que de l'accès aux blobs de `prod-data` ; une
personne qui n'y est pas dans `DEV` ne verra pas le groupe.

Ajouter, changer de niveau ou retirer quelqu'un est une PR, dont le plan
montre les attributions de rôle, puis un lancement manuel. La personne qui
tient le groupe n'est pas dans la liste : ses droits viennent de l'école
et du bootstrap.

Ce que le locataire de l'école ne permet pas : les groupes Entra ID (d'où
une ligne par personne) et la définition de rôles. Un niveau « tous
droits » serait `Owner` sur le groupe, que le rôle de l'école permettrait
techniquement d'attribuer, mais qui contournerait ce qu'elle a voulu
donner ; `devops` s'arrête donc au rôle Devops sur mesure.

## Travailler

```bash
cd terraform/DEV
terraform init
terraform plan
```

Un `apply` local est possible, mais la voie normale est la pull request,
où le plan est posté en commentaire, puis un **lancement manuel** de
l'apply depuis GitHub une fois la PR fusionnée. Appliquer à la main ce que
la CI applique aussi finit par deux vérités.

Vérifier le résultat sans clé, avec son identité :

```bash
sa=$(terraform output -raw storage_account_name)
az storage blob upload --auth-mode login --account-name "$sa" -c dev-data -f README.md -n test.md
az storage blob list   --auth-mode login --account-name "$sa" -c dev-data -o table
```

`AuthorizationPermissionMismatch` = rôle *Storage Blob Data* absent sur
ce conteneur (bootstrap pour vous, `team` pour les autres ; une à deux
minutes de propagation après l'apply). Un `RequestDisallowedByPolicy` au
plan ou à l'apply cite la stratégie de l'école en cause : région,
étiquette `user`, SKU, ou nombre de comptes.

## Nouvel environnement

Depuis GitHub : *Actions → terraform-new-env → Run workflow*, nom du
nouvel environnement et environnement modèle. Le workflow copie le dossier
et ouvre la pull request. Depuis un poste, la même chose :

```bash
bash terraform/scripts/new-env.sh DEV STAGING
```

Puis relire dans le dossier créé : `<ENV>.auto.tfvars` (abonnement,
groupe, compte du projet, équipe, conteneurs), `<ENV>.backend.tf` (où vit
son état, sur le compte du projet), `main.tf`. La CI découvre le dossier
seule, valide et planifie ; après fusion, l'apply se lance à la main.
Tous les environnements tiennent dans le même groupe : un conteneur de
plus, pas un compte.

**Dans un autre groupe de ressources**, si un jour il le faut : la
personne qui tient ce groupe ouvre la chaîne dessus, une fois, puis le nom
du groupe va dans `<ENV>.auto.tfvars`. L'état reste sur le compte du
projet :

```bash
bash terraform/scripts/allow-ci.sh rg-<login>_cours-projet-eadl
```

## Scripts

Cinq scripts. Les trois premiers sont idempotents : relancer ne casse
rien, complète ce qui manque. Chacun explique en tête ses étapes et ses réglages.

| Script | Quand | Ce qu'il fait |
| --- | --- | --- |
| `bootstrap.sh <groupe>` | une fois, par celui qui tient le groupe | Ce que Terraform ne peut pas créer lui-même : le compte de stockage du projet (sans clé, versions, corbeille) et son conteneur `tfstate` ; l'identité managée de la CI, ses identifiants fédérés GitHub et les mêmes rôles que vous sur le groupe ; votre accès aux blobs ; les deux secrets GitHub ; abonnement, groupe et compte écrits dans les `<ENV>.auto.tfvars` / `<ENV>.backend.tf` encore vierges |
| `allow-ci.sh <groupe>` | seulement si un environnement doit vivre dans un autre groupe | Donne à l'identité CI ses rôles sur ce groupe, et à lui l'accès aux blobs. Ni compte ni identité : l'état reste sur le compte du projet |
| `new-env.sh <SRC> <ENV>` | par nouvel environnement (ou le workflow *terraform-new-env*) | Copie le dossier d'un environnement, renomme ses fichiers, change la clé d'état et le nom. Ne touche pas à Azure |
| `issuer-keygen.sh <ENV>` | une fois par environnement, à la mise en place des identités applicatives, puis à chaque rotation | Génère la paire de clés de l'émetteur : clé privée hors du dépôt (vault Ansible), clé publique au format JWK à coller dans `<ENV>.auto.tfvars`. Ne touche pas à Azure |
| `workload-token.sh <clé> <issuer> <sujet>` | pour tester ou dépanner une identité applicative | Fabrique le même jeton que le code Python, à échanger avec `az login --federated-token` |
| `blob-demo.py <ENV> <identité>` | pour comprendre et démontrer | Le chemin complet en Python commenté : jeton signé, échange, puis lister / écrire / lire, avec ce que chaque identité obtient ou se voit refuser |

## Identités applicatives

Les API on-premise n'ont ni clé de compte ni secret Azure : une identité
managée par niveau de droit (`api-rw`, `api-ro`) fait confiance à un
émetteur de jetons à nous, une paire de clés par environnement dont la
clé privée reste dans le vault Ansible. Azure vérifie les jetons contre la
clé publique que Terraform publie sur le site statique du compte du
projet. Mise en place, code Python, test et rotation :
[docs/identites-applicatives.md](docs/identites-applicatives.md).

## CI/CD

`.github/workflows/terraform.yml`, déclenché seulement quand `terraform/`
change, environnement par environnement (un changement sous `modules/`
concerne tous) :

| Événement | Jobs | Ce que ça garantit |
| --- | --- | --- |
| pull request | `verify` (fmt, validate, tflint) puis `plan`, commenté sur la PR | Le changement est relu **avec** son effet réel sur Azure |
| lancement manuel (*Actions → terraform → Run workflow*) | `verify`, puis `plan` et `apply` de ce plan, sur l'environnement saisi | Rien ne s'applique sans qu'une personne l'ait décidé |
| lancement manuel (*Actions → terraform-new-env → Run workflow*) | `scripts/new-env.sh`, branche `env/<NOM>`, pull request ouverte | Un environnement se crée sans poste, et passe par la même revue |

Le commentaire de plan est unique par environnement et mis à jour à chaque
push : verdict en première ligne (rien à faire, changements, ou
**destructions** en rouge), lien vers le run, sortie complète repliée.

**Rien ne s'applique à la fusion.** Une fois la PR fusionnée, quelqu'un
ouvre *Actions → terraform → Run workflow*, choisit la branche `develop`
(`master` pour `PROD`) et saisit l'environnement. Le workflow refuse tout
autre couple branche/environnement, et l'identité Azure ne reconnaît de
toute façon que ces deux branches. C'est le pendant du `ansible-playbook
deploy.yml` lancé depuis un poste : la fusion rend le changement
déployable, le clic le déploie.

La version de Terraform est celle du `.terraform-version` de chaque
environnement. Un seul plan ou apply à la fois par environnement.

L'identité CI est une identité managée : elle ne détient aucun secret,
GitHub présente un jeton OIDC dont le sujet est « PR du dépôt », « branche
develop » ou « branche master », et Azure n'en échange pas d'autre. Elle a
les mêmes rôles que vous sur le groupe du bootstrap, et sur les seuls
autres groupes qu'un `allow-ci.sh` lui a ouverts.

Ce que le plan gratuit GitHub ne permet pas sur un dépôt privé : les
environnements protégés (approbation d'une seconde personne au moment de
l'apply). La relecture est celle de la PR, la décision celle du clic ; la
protection de branche manque, comme pour Ansible.
