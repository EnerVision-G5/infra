# Environnement de développement partagé
# Même groupe que le bootstrap. subscription_id et resource_group_name sont écrits par scripts/bootstrap.sh
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "dev"

# member : voit tout le groupe, lit les blobs
# devops : rôle Devops de l'école, écrit les blobs (état Terraform compris)
# object_id : az ad user show --id "prenom.nom@campus-eni.fr" --query id -o tsv
# Pas la personne qui tient le groupe (ses droits viennent de l'école)
team = {
  # "prenom.nom@campus-eni.fr" = { role = "devops", object_id = "00000000-0000-0000-0000-000000000000" }
  # "autre.nom@campus-eni.fr"  = { role = "member", object_id = "00000000-0000-0000-0000-000000000000" }
}

# Compte du projet (bootstrap) ; conteneurs préfixés : dev-data
storage_account_name = "stenervisiontfca5c57"
storage_containers   = ["data"]

# Identités (objectId) qui lisent et écrivent les blobs : applications, identités managées
storage_blob_contributor_principal_ids = []

# Identités applicatives (API on-premise) : une par niveau de droit, jeton
# signé par notre émetteur, aucun secret côté Azure. Voir docs/identites-applicatives.md.
#   1. bash terraform/scripts/issuer-keygen.sh DEV   → clé privée pour le vault Ansible,
#      et le bloc workload_issuer_jwks ci-dessous (clé publique, pas un secret)
#   2. après apply : terraform output workload_identities → client_id et sujet par API
blob_workloads = {
  "api-rw" = "rw"
  "api-ro" = "ro"
}
workload_issuer_jwks = null
