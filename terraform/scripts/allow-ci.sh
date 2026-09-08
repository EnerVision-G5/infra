#!/usr/bin/env bash
#
# Ouvrir un AUTRE groupe de ressources à la chaîne Terraform — par la
# personne qui tient ce groupe, une fois. Idempotent.
#
#   bash terraform/scripts/allow-ci.sh rg-<login>_cours-projet-eadl
#
# Cas d'usage : PROD dans le groupe d'un coéquipier, quand celui du
# bootstrap est plein (deux comptes de stockage par groupe) ou simplement
# pour séparer la production. L'état reste sur le compte du bootstrap ; ce
# script ne crée ni compte ni identité, il donne des rôles :
#   - à l'identité CI id-<projet>-github : les vôtres sur ce groupe, la
#     lecture, et l'accès aux blobs ;
#   - à vous : l'accès aux blobs, pour vérifier le résultat.
#
# Il faut voir l'identité CI, donc être au moins `member` du groupe du
# bootstrap. Réglages : PROJECT (enervision), CI_RG (groupe du bootstrap,
# détecté sinon).

set -euo pipefail

rg="${1:?usage : allow-ci.sh <groupe de ressources>}"
project="${PROJECT:-enervision}"
id_name="id-${project}-github"

assign() { # assign <objectId> <User|ServicePrincipal> <rôle> <portée>
  az role assignment create --assignee-object-id "$1" --assignee-principal-type "$2" \
    --role "$3" --scope "$4" --output none 2>/dev/null && echo "OK   $3" || echo "--   $3 (déjà attribué ou refusé)"
}

az account show >/dev/null 2>&1 || az login --output none
me="$(az ad signed-in-user show --query id -o tsv)"
rg_scope="$(az group show -n "$rg" --query id -o tsv)"

ci_rg="${CI_RG:-$(az identity list --query "[?name=='$id_name'].resourceGroup | [0]" -o tsv)}"
[ -n "$ci_rg" ] || { echo "Identité $id_name introuvable : demander l'accès member au groupe du bootstrap" >&2; exit 1; }
principal_id="$(az identity show -n "$id_name" -g "$ci_rg" --query principalId -o tsv)"

my_roles="$(az role assignment list --assignee "$me" --scope "$rg_scope" --include-inherited \
  --query "[?roleDefinitionName!='Reader'].roleDefinitionName" -o tsv | sort -u)"
[ -n "$my_roles" ] || { echo "Aucun rôle d'écriture sur $rg pour $me" >&2; exit 1; }

echo "Identité CI $id_name ($ci_rg) sur $rg :"
while IFS= read -r role; do
  [ -n "$role" ] && assign "$principal_id" ServicePrincipal "$role" "$rg_scope"
done <<< "$my_roles"
assign "$principal_id" ServicePrincipal "Reader" "$rg_scope"
assign "$principal_id" ServicePrincipal "Storage Blob Data Contributor" "$rg_scope"
echo "Vous, sur $rg :"
assign "$me" User "Storage Blob Data Contributor" "$rg_scope"

echo
echo "Dans <ENV>.auto.tfvars : resource_group_name = \"$rg\" (l'état reste sur le compte du bootstrap)."
