# terraform

Infrastructure Azure d'EnerVision. Périmètre actuel : un **compte de
stockage Blob** pour l'environnement `POC`. Rien ici ne touche la VM
on-premise, qui reste sous [Ansible](../ansible/) ; ce dossier est le
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
├── POC/                        un dossier par environnement (MAJUSCULES)
│   ├── .terraform-version      version de Terraform, lue par tfenv et par la CI
│   ├── .terraform.lock.hcl     versions des fournisseurs, verrouillées
│   ├── POC.auto.tfvars         valeurs de l'environnement : abonnement, groupe, briques
│   ├── POC.backend.tf          où vit l'état : compte partagé, clé POC.tfstate
│   ├── providers.tf            versions, fournisseur (sans identifiant)
│   ├── main.tf                 un appel du module projet, avec les valeurs de l'environnement
│   ├── variables.tf / outputs.tf
├── modules/
│   └── tf-module-enervision/   le projet : fichiers communs + un fichier par brique
│       ├── main.tf             groupe de ressources (fourni), noms, étiquettes
│       ├── variables.tf        commun, puis une section par brique
│       ├── outputs.tf
│       ├── storage.tf          compte Blob durci + conteneurs
│       └── iam.tf              droits d'identités applicatives sur le compte
├── scripts/
│   ├── bootstrap.sh            une fois par groupe de ressources : état, identité CI
│   ├── new-env.sh              nouvel environnement à partir d'un existant
│   └── grant.sh                donner ses droits à un coéquipier
├── docs/organisation-azure.md  ce que l'école donne et interdit, l'équipe, les droits
└── .tflint.hcl
```

Deux règles :

- **Un module projet, un dossier par environnement.** `POC/main.tf` ne
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
| Abonnement, groupe de ressources | `<ENV>.auto.tfvars` et `<ENV>.backend.tf`, écrits par le bootstrap | idem | idem |
| Identité | — | la session `az login` | `ARM_CLIENT_ID` + `ARM_TENANT_ID` + `ARM_USE_OIDC=true`, depuis les secrets `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` |
| Accès à l'état | `use_azuread_auth = true` | votre rôle *Storage Blob Data Contributor* sur le groupe | rôle de l'identité CI |

Ce que le groupe de l'école impose, et que le module respecte : région
`francecentral` seule, étiquette `user` égale à celle du groupe sur chaque
ressource (recopiée depuis le groupe), comptes de stockage en `Standard_LRS`,
et **deux comptes de stockage au plus** par groupe : celui de l'état, et
celui de l'environnement. Un second environnement demande donc un autre
groupe de ressources (celui d'un coéquipier, ou un abonnement à soi). Le
détail des droits et des interdits : [docs/organisation-azure.md](docs/organisation-azure.md).

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
d'état dans `POC/POC.auto.tfvars` et `POC/POC.backend.tf`. Puis, une
commande par coéquipier :

```bash
bash terraform/scripts/grant.sh rg-MCharge2024_cours-projet-eadl prenom.nom@campus-eni.fr
```

## Travailler

```bash
cd terraform/POC
terraform init
terraform plan
```

Un `apply` local est possible, mais la voie normale est la pull request :
le plan y est posté en commentaire, et la fusion applique exactement ce
plan. Appliquer à la main ce que la CI applique aussi finit par deux
vérités.

Vérifier le résultat sans clé, avec son identité :

```bash
sa=$(terraform output -raw storage_account_name)
az storage blob upload --auth-mode login --account-name "$sa" -c poc -f README.md -n test.md
az storage blob list   --auth-mode login --account-name "$sa" -c poc -o table
```

`AuthorizationPermissionMismatch` = rôle *Storage Blob Data Contributor*
absent sur le groupe (bootstrap pour vous, `grant.sh` pour les autres ;
une à deux minutes de propagation). Un `RequestDisallowedByPolicy` au plan
ou à l'apply cite la stratégie de l'école en cause : région, étiquette
`user`, SKU, ou nombre de comptes.

## Nouvel environnement

```bash
bash terraform/scripts/new-env.sh POC PROD
```

Puis relire dans `PROD/` : `PROD.auto.tfvars` (abonnement, groupe de
ressources, valeurs), `PROD.backend.tf` (où vit son état), `main.tf` (les
valeurs passées au module). Si le groupe est ailleurs, un bootstrap dessus.
Ouvrir une pull request : la CI découvre le dossier seule, valide,
planifie, et applique à la fusion.

## Scripts

Trois scripts, tous idempotents : relancer ne casse rien, complète ce qui
manque. Chacun explique en tête ses étapes et ses réglages.

| Script | Quand | Ce qu'il fait |
| --- | --- | --- |
| `bootstrap.sh <groupe>` | une fois par groupe de ressources, par celui qui le tient | Ce que Terraform ne peut pas créer lui-même : le compte d'état (sans clé, versions, corbeille) et son conteneur `tfstate` ; l'identité managée de la CI, ses identifiants fédérés GitHub et les mêmes rôles que vous sur le groupe ; votre accès aux blobs ; les deux secrets GitHub ; abonnement, groupe et compte d'état écrits dans les `<ENV>.auto.tfvars` / `<ENV>.backend.tf` encore vierges |
| `grant.sh <groupe> <courriel>` | une fois par coéquipier | Vos rôles d'écriture, la lecture et l'accès aux blobs (état compris) donnés à la personne sur le groupe |
| `new-env.sh <SRC> <ENV>` | par nouvel environnement | Copie le dossier d'un environnement, renomme ses fichiers, change la clé d'état et le nom. Ne touche pas à Azure |

## CI/CD

`.github/workflows/terraform.yml`, déclenché seulement quand `terraform/`
change, environnement par environnement (un changement sous `modules/`
concerne tous) :

| Événement | Jobs | Ce que ça garantit |
| --- | --- | --- |
| pull request | `verify` (fmt, validate, tflint) puis `plan`, commenté sur la PR | Le changement est relu **avec** son effet réel sur Azure |
| push `develop` | `plan` puis `apply` du plan, tous les environnements sauf `PROD` | Ce qui est sur `develop` est ce qui est sur Azure, comme `vars.yml` l'est pour la VM |
| push `master` | idem, `PROD` seulement | La production suit la branche de production |

La version de Terraform est celle du `.terraform-version` de chaque
environnement. Un seul plan ou apply à la fois par environnement.

L'identité CI est une identité managée : elle ne détient aucun secret,
GitHub présente un jeton OIDC dont le sujet est « PR du dépôt », « branche
develop » ou « branche master », et Azure n'en échange pas d'autre. Elle a
les mêmes rôles que vous, sur votre seul groupe de ressources.

Ce que le plan gratuit GitHub ne permet pas sur un dépôt privé : les
environnements protégés (revue obligatoire avant `apply`). La revue est
celle de la PR ; la protection de branche manque, comme pour Ansible.

## Aller plus loin

Un scan de configuration (trivy ou checkov) dans `verify` ; une identité
CI distincte en lecture seule pour le `plan` des PR ; fermer l'accès
réseau public du compte (le rôle de l'école autorise les réseaux virtuels,
pas les points de terminaison privés : à vérifier) ; un abonnement à soi
pour `PROD`, où le module recréerait les groupes et les équipes.
