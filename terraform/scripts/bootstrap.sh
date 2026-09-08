#!/usr/bin/env bash
#
# Amorçage — UNE fois par groupe de ressources, par la personne qui le tient.
# Idempotent : relancer ne casse rien, complète ce qui manque.
#
#   bash terraform/scripts/bootstrap.sh rg-MCharge2024_cours-projet-eadl
#
# Le groupe de ressources est FOURNI (par l'école, ou créé à la main dans un
# abonnement à soi) : rien ici ne demande de droit au-delà. Terraform ne
# peut pas créer ce dont il dépend pour tourner ; c'est tout ce que fait ce
# script, et un nouvel environnement n'a jamais besoin d'y repasser :
#
#   1. le compte de stockage du projet : sans clé partagée, versions et
#      corbeille ; il porte l'état (conteneur tfstate) et, par Terraform, un
#      conteneur par environnement (l'école plafonne les comptes à deux) ;
#   2. l'identité de la CI : identité managée + identifiants fédérés GitHub
#      (OIDC, aucun secret), avec les mêmes rôles que vous sur le groupe ;
#   3. vos propres droits de données sur les blobs (plan local, vérifs) ;
#   4. les secrets GitHub (des identifiants, pas des clés) et les valeurs
#      dans les <ENV>.backend.tf / <ENV>.auto.tfvars encore vierges.
#
# Réglages : PROJECT (enervision), GITHUB_REPO (EnerVision-G5/infra),
# APPLY_BRANCHES (develop master).

set -euo pipefail

rg="${1:?usage : bootstrap.sh <groupe de ressources>}"
project="${PROJECT:-enervision}"
github_repo="${GITHUB_REPO:-EnerVision-G5/infra}"
apply_branches="${APPLY_BRANCHES:-develop master}"

tf_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
placeholder_sub="00000000-0000-0000-0000-000000000000"

say() { printf '\n==> %s\n' "$*"; }
assign() { # assign <objectId> <User|ServicePrincipal> <rôle> <portée>
  az role assignment create --assignee-object-id "$1" --assignee-principal-type "$2" \
    --role "$3" --scope "$4" --output none 2>/dev/null || true
}
# sed -i portable (BSD et GNU)
edit() { local f="$1"; shift; sed "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

command -v az >/dev/null || { echo "Azure CLI absente : brew install azure-cli" >&2; exit 1; }
az account show >/dev/null 2>&1 || az login --output none

sub_id="$(az account show --query id -o tsv)"
tenant_id="$(az account show --query tenantId -o tsv)"
me="$(az ad signed-in-user show --query id -o tsv)"
say "Abonnement $(az account show --query name -o tsv) ($sub_id)"

# --- 0. Le groupe et ce qu'il impose ----------------------------------------------
rg_scope="$(az group show -n "$rg" --query id -o tsv)" \
  || { echo "Groupe introuvable ou illisible : $rg" >&2; exit 1; }
location="$(az group show -n "$rg" --query location -o tsv)"
# Étiquette `user` : une stratégie de l'école refuse toute ressource qui ne
# porte pas celle du groupe. Vide ailleurs, et alors sans effet.
user_tag="$(az group show -n "$rg" --query 'tags.user' -o tsv 2>/dev/null || true)"
tag_args=(--tags project="$project" managed_by=bootstrap)
[ -n "$user_tag" ] && tag_args+=(user="$user_tag")

# Vos rôles sur le groupe, hors lecture : l'identité CI recevra les mêmes.
my_roles="$(az role assignment list --assignee "$me" --scope "$rg_scope" --include-inherited \
  --query "[?roleDefinitionName!='Reader'].roleDefinitionName" -o tsv | sort -u)"
[ -n "$my_roles" ] || { echo "Aucun rôle d'écriture sur $rg pour $me" >&2; exit 1; }
say "Groupe $rg ($location) — vos rôles : $(printf '%s' "$my_roles" | tr '\n' ',' | sed 's/,$//')"

# --- 1. Compte de stockage du projet -------------------------------------------------
# Suffixe déterministe (début de l'identifiant d'abonnement) : unique au monde,
# identique à chaque relance, rien à retenir.
state_sa="st${project}tf$(printf '%s' "$sub_id" | tr -d - | cut -c1-6)"
say "Compte du projet : $rg / $state_sa (état dans tfstate)"
if ! az storage account show -n "$state_sa" -g "$rg" >/dev/null 2>&1; then
  az storage account create -n "$state_sa" -g "$rg" -l "$location" \
    --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --https-only true \
    --allow-blob-public-access false --allow-shared-key-access false \
    "${tag_args[@]}" purpose=tfstate --output none
fi
# Versions + corbeille 30 jours : un état écrasé se retrouve.
az storage account blob-service-properties update --account-name "$state_sa" -g "$rg" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 --output none

# --- 3. (avant 2) vos droits de données : sans clé partagée, même le rôle
#        d'écriture du groupe ne suffit pas pour créer le conteneur --------------
assign "$me" User "Storage Blob Data Contributor" "$rg_scope"
for _ in 1 2 3 4 5 6; do
  az storage container create -n tfstate --account-name "$state_sa" \
    --auth-mode login --output none 2>/dev/null && break
  sleep 15
done

# --- 2. Identité de la CI (OIDC GitHub) ----------------------------------------------
# Identité managée, pas d'app registration : le locataire de l'école interdit
# ces dernières aux utilisateurs, et une identité managée porte aussi des
# identifiants fédérés. Un par contexte GitHub autorisé à obtenir un jeton :
# les pull requests (plan) et chaque branche d'application (apply). Azure
# n'échange rien d'autre. Ni mot de passe ni certificat, nulle part.
id_name="id-${project}-github"
say "Identité CI : $id_name"
az identity create -n "$id_name" -g "$rg" -l "$location" "${tag_args[@]}" --output none
client_id="$(az identity show -n "$id_name" -g "$rg" --query clientId -o tsv)"
principal_id="$(az identity show -n "$id_name" -g "$rg" --query principalId -o tsv)"

fed_cred() { # fed_cred <nom> <sujet>
  az identity federated-credential create --name "$1" --identity-name "$id_name" -g "$rg" \
    --issuer "https://token.actions.githubusercontent.com" --subject "$2" \
    --audiences "api://AzureADTokenExchange" --output none 2>/dev/null \
    || az identity federated-credential update --name "$1" --identity-name "$id_name" -g "$rg" \
      --issuer "https://token.actions.githubusercontent.com" --subject "$2" \
      --audiences "api://AzureADTokenExchange" --output none
}
# Le sujet présenté par GitHub porte les identifiants numériques du
# propriétaire et du dépôt (repo:ORG@id/DEPOT@id:…), qui survivent à un
# renommage. Sans `gh`, repli sur la forme courte, qu'Azure ne reconnaît
# plus : le plan de la PR échouerait alors sur AADSTS700213.
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  owner_id="$(gh api "repos/${github_repo}" --jq '.owner.id')"
  repo_id="$(gh api "repos/${github_repo}" --jq '.id')"
  subject_prefix="repo:${github_repo%%/*}@${owner_id}/${github_repo##*/}@${repo_id}"
else
  echo "gh absent : sujets OIDC sans identifiants numériques, à corriger à la main" >&2
  subject_prefix="repo:${github_repo}"
fi
fed_cred "github-pull-request" "${subject_prefix}:pull_request"
for branch in $apply_branches; do
  fed_cred "github-branch-${branch}" "${subject_prefix}:ref:refs/heads/${branch}"
done

# Mêmes rôles que vous sur le groupe, plus la lecture et l'état.
while IFS= read -r role; do
  [ -n "$role" ] && assign "$principal_id" ServicePrincipal "$role" "$rg_scope"
done <<< "$my_roles"
assign "$principal_id" ServicePrincipal "Reader" "$rg_scope"
assign "$principal_id" ServicePrincipal "Storage Blob Data Contributor" "$rg_scope"

# --- 4. Secrets GitHub et fichiers d'environnement ------------------------------------
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  say "Secrets GitHub sur $github_repo"
  gh secret set AZURE_CLIENT_ID -R "$github_repo" --body "$client_id"
  gh secret set AZURE_TENANT_ID -R "$github_repo" --body "$tenant_id"
else
  say "gh absent ou non connecté : créer les secrets du dépôt $github_repo à la main"
  echo "  AZURE_CLIENT_ID = $client_id"
  echo "  AZURE_TENANT_ID = $tenant_id"
fi

say "Environnements encore vierges (abonnement $placeholder_sub) : valeurs reportées"
for f in "$tf_root"/*/*.backend.tf "$tf_root"/*/*.auto.tfvars; do
  if ! { [ -f "$f" ] && grep -q "$placeholder_sub" "$f"; }; then continue; fi
  edit "$f" \
    -e "s|\"$placeholder_sub\"|\"$sub_id\"|" \
    -e "s|resource_group_name  = \"[^\"]*\"|resource_group_name  = \"$rg\"|" \
    -e "s|^resource_group_name = \"[^\"]*\"|resource_group_name = \"$rg\"|" \
    -e "s|storage_account_name = \"[^\"]*\"|storage_account_name = \"$state_sa\"|"
  echo "  $f"
done
command -v terraform >/dev/null && terraform fmt -recursive "$tf_root" >/dev/null

say "Terminé. Suite :"
echo "  cd terraform/DEV && terraform init && terraform plan"
echo "  coéquipiers : team dans DEV/DEV.auto.tfvars (az ad user show --id <courriel> --query id -o tsv)"
