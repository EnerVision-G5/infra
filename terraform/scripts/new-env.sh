#!/usr/bin/env bash
#
# Nouvel environnement à partir d'un existant :
#
#   bash terraform/scripts/new-env.sh POC PROD
#
# Copie le dossier, renomme <SRC>.auto.tfvars / <SRC>.backend.tf, change la
# clé d'état et le nom d'environnement. Ne touche pas à Azure : la CI crée
# le groupe de ressources et tout le reste au premier apply.
#
# Restent à relire dans le dossier créé, à la main :
#   - <ENV>.auto.tfvars : subscription_id si l'environnement vit dans un autre
#     abonnement (alors bootstrap.sh y est à rejouer), et les valeurs propres ;
#   - <ENV>.backend.tf  : subscription_id de l'état, même remarque ;
#   - main.tf           : les briques que cet environnement porte.
#
# Convention : dossier en MAJUSCULES, `environment` en minuscules.

set -euo pipefail

src="${1:?usage : new-env.sh <SRC> <ENV>   ex. new-env.sh POC PROD}"
env_name="${2:?usage : new-env.sh <SRC> <ENV>   ex. new-env.sh POC PROD}"
env_lower="$(printf '%s' "$env_name" | tr '[:upper:]' '[:lower:]')"
src_lower="$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')"

tf_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$tf_root/$src"
dst_dir="$tf_root/$env_name"

[ -d "$src_dir" ] || { echo "Environnement source absent : $src_dir" >&2; exit 1; }
[ ! -e "$dst_dir" ] || { echo "Existe déjà : $dst_dir" >&2; exit 1; }
printf '%s' "$env_name" | grep -Eq '^[A-Z0-9]{2,6}$' || { echo "Nom : 2 à 6 caractères [A-Z0-9]" >&2; exit 1; }

mkdir "$dst_dir"
# Ni l'état local du fournisseur (.terraform/) ni les plans : que le code, le
# verrou de versions et le pin de Terraform.
for f in "$src_dir"/*.tf "$src_dir/.terraform-version" "$src_dir/.terraform.lock.hcl"; do
  [ -f "$f" ] && cp "$f" "$dst_dir/"
done
mv "$dst_dir/$src.backend.tf" "$dst_dir/$env_name.backend.tf"
cp "$src_dir/$src.auto.tfvars" "$dst_dir/$env_name.auto.tfvars"

# sed portable (BSD et GNU) : édition via fichier temporaire.
edit() { # edit <fichier> <expr sed>…
  local file="$1"; shift
  sed "$@" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}
edit "$dst_dir/$env_name.backend.tf" \
  -e "s|key *= *\"$src.tfstate\"|key                  = \"$env_name.tfstate\"|" \
  -e "s|environnement $src\.|environnement $env_name.|"
edit "$dst_dir/$env_name.auto.tfvars" \
  -e "s|^environment *= *\"$src_lower\"|environment     = \"$env_lower\"|" \
  -e "s|environnement $src\.|environnement $env_name.|" \
  -e "s|ce que $src contient|ce que $env_name contient|"
edit "$dst_dir/main.tf" -e "s|^# Environnement $src :|# Environnement $env_name :|"

command -v terraform >/dev/null && terraform fmt "$dst_dir" >/dev/null

echo "Créé : $dst_dir"
echo
echo "À relire : $env_name.auto.tfvars (subscription_id, valeurs), $env_name.backend.tf, main.tf."
echo "Puis une pull request : la CI valide et planifie ; après fusion, apply par lancement manuel (README, CI/CD)."
