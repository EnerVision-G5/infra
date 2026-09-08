# terraform

Infrastructure Azure d'EnerVision. Périmètre actuel : un **compte de
stockage Blob** par environnement, `DEV` et `PROD`. Rien ici ne touche la
VM on-premise, qui reste sous [Ansible](../ansible/) ; ce dossier est le
pendant cloud, avec la même logique.

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
│   ├── DEV.backend.tf          où vit l'état : compte partagé, clé DEV.tfstate
│   ├── providers.tf            versions, fournisseur (sans identifiant)
│   ├── main.tf                 un appel du module projet, avec les valeurs de l'environnement
│   ├── variables.tf / outputs.tf
├── PROD/                       même structure, appliqué depuis master
├── modules/
│   └── tf-module-enervision/   le projet : fichiers communs + un fichier par brique
│       ├── main.tf             groupe de ressources (fourni), noms, étiquettes
│       ├── variables.tf        commun, puis une section par brique
│       ├── outputs.tf
│       ├── storage.tf          compte Blob durci + conteneurs
│       └── iam.tf              droits de l'équipe sur le groupe, d'identités sur le compte
├── scripts/
│   ├── bootstrap.sh            une fois : état, identité CI, sur le premier groupe
│   ├── allow-ci.sh             ouvrir un autre groupe de ressources à la chaîne
│   └── new-env.sh              nouvel environnement à partir d'un existant
├── docs/organisation-azure.md  ce que l'école donne et interdit, l'équipe, les droits
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
  crée tout et ne peut rien toucher ailleurs, l'identité CI non plus. Le
  seul geste manuel de la chaîne est le bootstrap, une fois par groupe.

## Configuration

Le fournisseur ne lit **aucun identifiant dans le code** :

| Quoi | Où | En local | En CI |
| --- | --- | --- | --- |
| Abonnement, groupe de ressources | `<ENV>.auto.tfvars` et `<ENV>.backend.tf`, écrits par le bootstrap pour le premier environnement, recopiés pour les suivants | idem | idem |
| Identité | — | la session `az login` | `ARM_CLIENT_ID` + `ARM_TENANT_ID` + `ARM_USE_OIDC=true`, depuis les secrets `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` |
| Accès à l'état | `use_azuread_auth = true` | votre rôle *Storage Blob Data Contributor* sur le groupe | rôle de l'identité CI |

Ce que le groupe de l'école impose, et que le module respecte : région
`francecentral` seule, étiquette `user` égale à celle du groupe sur chaque
ressource (recopiée depuis le groupe), comptes de stockage en `Standard_LRS`,
et **deux comptes de stockage au plus** par groupe : celui de l'état plus
un environnement. `DEV` vit dans le groupe du bootstrap ; `PROD` va dans
un autre groupe, celui d'un coéquipier (voir *Nouvel environnement*), ce
qui sépare de toute façon la production du développement. Le détail des
droits et des interdits : [docs/organisation-azure.md](docs/organisation-azure.md).

Conventions, celles du
[Cloud Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) :
`st<projet><env><suffixe>` (ni tiret ni majuscule, unique au monde :
suffixe aléatoire gardé dans l'état), `id-<projet>-github`. Étiquettes
partout : `project`, `environment`, `managed_by`, `repository`, `user`.

## Démarrer (une fois, celui qui tient le groupe)

```bash
bash terraform/scripts/bootstrap.sh rg-MCharge2024_cours-projet-eadl
```

Le script crée le compte d'état, l'identité managée de la CI avec ses
identifiants fédérés GitHub et les mêmes rôles que vous sur le groupe,
pousse les deux secrets GitHub, et écrit abonnement, groupe et compte
d'état dans `DEV/DEV.auto.tfvars` et `DEV/DEV.backend.tf`.

## L'équipe

Même logique qu'un projet GCP : le groupe de ressources est le projet, les
gens s'y voient donner un niveau, et se connectent avec leur propre compte
(campus) pour le voir dans le portail. Deux niveaux, dans `team` du
`<ENV>.auto.tfvars` de chaque environnement (la production n'a pas
forcément les mêmes `devops` que le développement) :

| Niveau | Comme sur GCP | Rôles Azure posés sur le groupe |
| --- | --- | --- |
| `member` | viewer | `Reader`, `Storage Blob Data Reader` : voit tout, lit les blobs |
| `devops` | editor | `Reader`, `Devops-cours-projet-eadl` (le rôle de l'école, celui que vous tenez), `Storage Blob Data Contributor` : crée, modifie, écrit les blobs, état Terraform compris |

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
az storage blob upload --auth-mode login --account-name "$sa" -c dev -f README.md -n test.md
az storage blob list   --auth-mode login --account-name "$sa" -c dev -o table
```

`AuthorizationPermissionMismatch` = rôle *Storage Blob Data Contributor*
absent sur le groupe (bootstrap pour vous, `team` pour les autres ;
une à deux minutes de propagation après l'apply). Un `RequestDisallowedByPolicy` au plan
ou à l'apply cite la stratégie de l'école en cause : région, étiquette
`user`, SKU, ou nombre de comptes.

## Nouvel environnement

Depuis GitHub : *Actions → terraform-new-env → Run workflow*, nom du
nouvel environnement et environnement modèle. Le workflow copie le dossier
et ouvre la pull request. Depuis un poste, la même chose :

```bash
bash terraform/scripts/new-env.sh DEV STAGING
```

Puis relire dans le dossier créé : `<ENV>.auto.tfvars` (abonnement,
groupe de ressources, équipe, briques), `<ENV>.backend.tf` (où vit son
état, sur le compte du bootstrap), `main.tf`. La CI découvre le dossier
seule, valide et planifie ; après fusion, l'apply se lance à la main.

**Dans un autre groupe de ressources** (le cas de `PROD`) : la personne
qui tient ce groupe ouvre la chaîne dessus, une fois, puis le nom du
groupe va dans `<ENV>.auto.tfvars`. L'état reste sur le compte du
bootstrap, rien d'autre à créer :

```bash
bash terraform/scripts/allow-ci.sh rg-<login>_cours-projet-eadl
```

## Scripts

Trois scripts, tous idempotents : relancer ne casse rien, complète ce qui
manque. Chacun explique en tête ses étapes et ses réglages.

| Script | Quand | Ce qu'il fait |
| --- | --- | --- |
| `bootstrap.sh <groupe>` | une fois, sur le premier groupe, par celui qui le tient | Ce que Terraform ne peut pas créer lui-même : le compte d'état (sans clé, versions, corbeille) et son conteneur `tfstate` ; l'identité managée de la CI, ses identifiants fédérés GitHub et les mêmes rôles que vous sur le groupe ; votre accès aux blobs ; les deux secrets GitHub ; abonnement, groupe et compte d'état écrits dans les `<ENV>.auto.tfvars` / `<ENV>.backend.tf` encore vierges |
| `allow-ci.sh <groupe>` | une fois par groupe supplémentaire, par celui qui le tient | Donne à l'identité CI ses rôles sur ce groupe, et à lui l'accès aux blobs. Ni compte ni identité : l'état reste sur le compte du bootstrap |
| `new-env.sh <SRC> <ENV>` | par nouvel environnement (ou le workflow *terraform-new-env*) | Copie le dossier d'un environnement, renomme ses fichiers, change la clé d'état et le nom. Ne touche pas à Azure |

## CI/CD

`.github/workflows/terraform.yml`, déclenché seulement quand `terraform/`
change, environnement par environnement (un changement sous `modules/`
concerne tous) :

| Événement | Jobs | Ce que ça garantit |
| --- | --- | --- |
| pull request | `verify` (fmt, validate, tflint) puis `plan`, commenté sur la PR | Le changement est relu **avec** son effet réel sur Azure |

Le commentaire de plan est unique par environnement et mis à jour à chaque
push : verdict en première ligne (rien à faire, changements, ou
**destructions** en rouge), lien vers le run, sortie complète repliée.
| lancement manuel (*Actions → terraform → Run workflow*) | `verify`, puis `plan` et `apply` de ce plan, sur l'environnement saisi | Rien ne s'applique sans qu'une personne l'ait décidé |

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
les mêmes rôles que vous, sur votre seul groupe de ressources.

Ce que le plan gratuit GitHub ne permet pas sur un dépôt privé : les
environnements protégés (approbation d'une seconde personne au moment de
l'apply). La relecture est celle de la PR, la décision celle du clic ; la
protection de branche manque, comme pour Ansible.

## Aller plus loin

Un scan de configuration (trivy ou checkov) dans `verify` ; une identité
CI distincte en lecture seule pour le `plan` des PR ; fermer l'accès
réseau public du compte (le rôle de l'école autorise les réseaux virtuels,
pas les points de terminaison privés : à vérifier) ; un abonnement à soi
pour `PROD`, où le module recréerait les groupes et les équipes.
