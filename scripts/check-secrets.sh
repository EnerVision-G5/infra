#!/usr/bin/env bash
#
# Vérifie qu'aucun secret sensible n'est stocké en clair dans le dépôt.
#
#   - le fichier Vault est bien chiffré avec ansible-vault ;
#   - les variables sensibles ne sont définies que par indirection Vault
#     (`clef: "{{ vault_... }}"`) hors du fichier Vault lui-même ;
#   - aucun placeholder « A_REMPLACER » / « REMPLACER » ne subsiste hors du
#     Vault chiffré ;
#   - gitleaks ne détecte rien (si l'outil est disponible).
#
# Sortie non nulle => un secret potentiellement en clair a été trouvé.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

vault_file="ansible/inventories/on-premise/group_vars/all/vault.yml"
status=0

note_error() {
  echo "::error::$*"
  status=1
}

# Fichiers versionnés OU déjà présents dans l'arbre et non ignorés (pour que le
# script soit utile aussi bien en CI qu'en local avant `git add`).
tracked() {
  git ls-files --cached --others --exclude-standard -- "$@" \
    | sort -u | while IFS= read -r f; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
}

# 1. Le fichier Vault existe et est chiffré.
if [[ ! -f "$vault_file" ]]; then
  note_error "Fichier Vault absent : $vault_file"
elif ! head -n 1 "$vault_file" | grep -q '^\$ANSIBLE_VAULT'; then
  note_error "$vault_file n'est pas chiffré avec ansible-vault"
else
  echo "OK   $vault_file est chiffré"
fi

# Fichiers YAML du dépôt, hors Vault.
mapfile -t yaml_files < <(tracked '*.yml' '*.yaml' | grep -vF "$vault_file" || true)

# 2. Variables sensibles : seules les affectations en indirection Vault sont
#    autorisées hors du Vault.
secret_vars=(
  garage_rpc_secret
  garage_admin_token
  garage_metrics_token
  postgres_password
  ghcr_username
  ghcr_token
  monitoring_grafana_admin_password
  applications_api_jwt_secret
  mlflow_azure_connection_string
  applications_workload_key
  ansible_password
)

for var in "${secret_vars[@]}"; do
  while IFS=: read -r file line content; do
    [[ -z "${file:-}" ]] && continue
    # Autorisé : `var: "{{ vault_... }}"` (guillemets optionnels).
    if [[ "$content" =~ ^[[:space:]]*${var}:[[:space:]]*\"?\{\{[[:space:]]*vault_ ]]; then
      continue
    fi
    note_error "$file:$line — '$var' semble défini en clair : ${content# }"
  done < <(grep -nE "^[[:space:]]*${var}:[[:space:]]*[^[:space:]]" "${yaml_files[@]}" 2>/dev/null || true)
done

# 3. Aucun placeholder de secret résiduel dans les vars / templates suivis
#    (hors Vault chiffré et hors ce script).
mapfile -t scannable < <(
  tracked '*.yml' '*.yaml' '*.j2' '*.cfg' '*.env.example' \
    | grep -vF "$vault_file" || true
)
if [[ "${#scannable[@]}" -gt 0 ]] \
  && grep -nE '(A_REMPLACER|REMPLACER_[a-z])' "${scannable[@]}"; then
  note_error "Placeholder de secret trouvé en clair (voir lignes ci-dessus)"
fi

# 4. gitleaks, si présent.
if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks detect --no-banner --redact --source .; then
    note_error "gitleaks a détecté un secret potentiel"
  fi
else
  echo "INFO gitleaks non installé — scan générique ignoré"
fi

if [[ "$status" -eq 0 ]]; then
  echo "Aucun secret en clair détecté."
fi
exit "$status"
