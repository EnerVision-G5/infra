#!/usr/bin/env bash
#
# Donner à un coéquipier les mêmes droits que vous sur le groupe de
# ressources. Une commande par personne, par celui qui tient le groupe.
#
#   bash terraform/scripts/grant.sh rg-MCharge2024_cours-projet-eadl prenom.nom@campus-eni.fr
#
# Dans le locataire de l'école, tout le monde existe déjà (compte campus) et
# personne ne peut créer de groupe Entra ID : les droits se donnent donc par
# personne, sur le groupe de ressources, et rien au-delà. La personne reçoit
# vos rôles d'écriture, la lecture, et l'accès aux blobs (état Terraform
# compris). Pour retirer quelqu'un :
#   az role assignment delete --assignee <courriel> --resource-group <groupe>

set -euo pipefail

rg="${1:?usage : grant.sh <groupe de ressources> <courriel>}"
email="${2:?usage : grant.sh <groupe de ressources> <courriel>}"

az account show >/dev/null 2>&1 || az login --output none

rg_scope="$(az group show -n "$rg" --query id -o tsv)"
me="$(az ad signed-in-user show --query id -o tsv)"
who="$(az ad user show --id "$email" --query id -o tsv 2>/dev/null || true)"
if [ -z "$who" ]; then
  who="$(az ad user list --filter "mail eq '$email'" --query '[0].id' -o tsv)"
fi
[ -n "$who" ] || { echo "Utilisateur introuvable dans le locataire : $email" >&2; exit 1; }

my_roles="$(az role assignment list --assignee "$me" --scope "$rg_scope" --include-inherited \
  --query "[?roleDefinitionName!='Reader'].roleDefinitionName" -o tsv | sort -u)"

for role in "Reader" "Storage Blob Data Contributor" $my_roles; do
  az role assignment create --assignee-object-id "$who" --assignee-principal-type User \
    --role "$role" --scope "$rg_scope" --output none 2>/dev/null \
    && echo "OK   $role" || echo "--   $role (déjà attribué ou refusé)"
done

echo
echo "Côté coéquipier, après une à deux minutes :"
echo "  az login --tenant $(az account show --query tenantId -o tsv)"
echo "  az group show -n $rg -o table"
echo "  cd terraform/POC && terraform init && terraform plan"
