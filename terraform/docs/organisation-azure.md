# Organiser Azure pour l'équipe

Azure n'a pas d'« organisation » au sens GitHub, et il n'y a rien à créer
avant de commencer. Ce qui en tient lieu, et ce que l'école en donne :

| Niveau | Ce que c'est | Ce qu'on a |
| --- | --- | --- |
| **Locataire** (Microsoft Entra ID) | L'annuaire : qui existe, avec quel compte | Celui de l'école : toute l'équipe y est déjà, avec son compte campus |
| **Abonnement** | L'unité de facturation et de quotas | Un abonnement à l'usage tenu par l'école, sans droit dessus |
| **Groupe de ressources** | Un dossier de ressources, et l'unité des droits | Un par étudiant (`rg-<login>_cours-projet-eadl`), avec un rôle sur mesure |
| **Groupe Entra ID** | Un ensemble de personnes | Interdit à la création : les droits se donnent par personne |

## Ce que le rôle de l'école permet et interdit

Relevé le 2026-09-07 sur `rg-MCharge2024_cours-projet-eadl` (rôle
`Devops-cours-projet-eadl` + `Reader`, stratégie `Devops-cours-projet-eadl`).

| Permis dans le groupe | Interdit |
| --- | --- |
| Comptes de stockage et blobs, Key Vault, identités managées, registre de conteneurs, machines virtuelles et disques, réseaux virtuels, IP publiques, Cosmos DB, Data Factory, Log Analytics, Application Insights, déploiements ARM, **attribution de rôles sur le groupe** | Créer un groupe de ressources ; Container Apps, App Service, PostgreSQL flexible ; app registrations et groupes Entra ID ; tout ce qui est hors du groupe |

Et ce que la stratégie impose sur chaque ressource : région `France Central`,
étiquette `user` égale à celle du groupe, comptes de stockage `Standard_LRS`,
au plus 2 comptes de stockage, 2 machines virtuelles, 1 registre, 1 IP
publique. Un refus se lit `RequestDisallowedByPolicy`, avec le nom de la
règle.

Deux conséquences sur la chaîne : l'identité de la CI est une **identité
managée** (pas d'app registration possible), et l'équipe reçoit ses droits
**personne par personne** sur le groupe, par script.

## 1. Amorcer (celui qui tient le groupe, une fois)

```bash
az login                      # compte campus
bash terraform/scripts/bootstrap.sh rg-MCharge2024_cours-projet-eadl
```

Pas de budget à poser : l'abonnement est celui de l'école. Le compte de
stockage du POC coûte quelques centimes par mois.

## 2. Donner l'accès à l'équipe

Comme sur un projet GCP : chacun garde son compte (campus), reçoit un
niveau sur le groupe de ressources, et le voit dans le portail. Les droits
sont dans le code, dans `team` de `terraform/POC/POC.auto.tfvars` : une
ligne par personne, son courriel, son niveau (`member` voit et lit,
`devops` fait tout ce que vous faites) et son objectId :

```bash
az ad user show --id prenom.nom@campus-eni.fr --query id -o tsv
```

Une PR, son plan montre les attributions de rôle, le lancement manuel les
applique. Un `member` peut relire les PR avec le plan sous les yeux et
lire les blobs ; un `devops` peut en plus faire `terraform plan` en local,
écrire les blobs, créer des ressources. Ni l'un ni l'autre ne peut rien
hors du groupe, comme vous.

## 3. Qui a quoi

| Qui | Rôles | Portée | Posé par |
| --- | --- | --- | --- |
| Vous | `Devops-cours-projet-eadl`, `Reader` | votre groupe | l'école |
| Vous | `Storage Blob Data Contributor` | votre groupe | `bootstrap.sh` |
| Coéquipier `member` | `Reader`, `Storage Blob Data Reader` | votre groupe | Terraform (`iam.tf`, liste `team`) |
| Coéquipier `devops` | `Reader`, `Devops-cours-projet-eadl`, `Storage Blob Data Contributor` | votre groupe | Terraform (`iam.tf`, liste `team`) |
| Identité CI `id-enervision-github` | les mêmes trois | votre groupe | `bootstrap.sh` |
| Identités applicatives (plus tard) | `Storage Blob Data Contributor` | le compte de l'environnement | Terraform (`iam.tf`) |

## 4. Vérifier

Un coéquipier, une à deux minutes après l'apply :

```bash
az login --tenant 7f4f3591-5f6c-4f7b-a1bd-0a2dd8831218
az group show -n rg-MCharge2024_cours-projet-eadl -o table
cd terraform/POC && terraform init && terraform plan
```

## 5. Quand quelqu'un part

Sa ligne en moins dans `team`, une PR, un apply : Terraform retire ses
rôles.

## Si un jour l'abonnement est à vous

Un compte Azure personnel ou d'entreprise (Owner de l'abonnement) lève
tous les interdits ci-dessus : groupes Entra ID, app registrations,
création de groupes de ressources, tous les services. Le même bootstrap
tourne sur un groupe créé à la main ; les personnes s'invitent alors comme
invités B2B (*Entra ID → Utilisateurs → Inviter un utilisateur externe*)
et un groupe Entra ID par niveau remplace la liste `team`.
