# Production
# Même groupe que le bootstrap. subscription_id et resource_group_name sont écrits par scripts/bootstrap.sh
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "prod"

# member : voit tout le groupe, lit les blobs
# devops : rôle Devops de l'école, écrit les blobs (état Terraform compris)
# object_id : az ad user show --id "prenom.nom@campus-eni.fr" --query id -o tsv
# Pas la personne qui tient le groupe (ses droits viennent de l'école)
# Rôles de groupe et accès à l'état : posés par DEV, pas ici. Cette liste
# ne décide que de l'accès aux blobs de prod-data.
project_roles = false

team = {
  "maxence.lemoine2024@campus-eni.fr" = { role = "devops", object_id = "ffaa1e68-ece5-4b8c-a5dd-d3ad9b6ac484" },
  "paul.laine2024@campus-eni.fr"      = { role = "member", object_id = "49ccb8cd-ba48-401f-96f7-707112a52d44" },
  "landry.guillet2023@campus-eni.fr"  = { role = "member", object_id = "ac9418af-bec4-48a1-a701-6ad85e7fca5e" }
}

# Compte du projet (bootstrap) ; conteneurs préfixés : prod-data
# Le rôle Ansible `backup` (restic) partage prod-data sous le préfixe
# `restic/` — quota de conteneurs limité pendant l'examen.
storage_account_name = "stenervisiontfca5c57"
storage_containers   = ["data"]

# Identités (objectId) qui lisent et écrivent les blobs : applications, identités managées
storage_blob_contributor_principal_ids = []

# Identités applicatives (API on-premise) : une par niveau de droit, jeton
# signé par notre émetteur, aucun secret côté Azure. Voir docs/identites-applicatives.md.
#   1. bash terraform/scripts/issuer-keygen.sh PROD   → clé privée pour le vault Ansible,
#      et le bloc workload_issuer_jwks ci-dessous (clé publique, pas un secret)
#   2. après apply : terraform output workload_identities → client_id et sujet par API
blob_workloads = {
  "api-rw" = "rw"
  "api-ro" = "ro"
}
workload_issuer_jwks = {
  kid = "prod-20260908"
  n   = "xAbDWcuQVkOHnsH5Ov52-a1rcbx5COqGaQ0gAaYp-t-OOOeSEhvS2Efb8-KctaNaUQptfsyLyUZIF9sl-B5tl7nD-yUHxPUbWY10ht60Ds3vSHwKkDWSb9hY90VzOp8yopJtTGf8F_I0ROBW60JSyBRV21S1X5ykTwE_kw480AsYVb_F923uxSoHDXEFgEMKzWOVGF6p1TOrnOge0WF3FIid2prpgqim2UCTYjXfK7eciuLIQuFHCbf7cbrTYmwkRkg-BcEBKXoMy1btXcr37VbjpbfjJWrP3oT3IBkEd5G8XhmE9UBx14GZ8LQeR7DBTi2LX2kD1NhWtHacX6a2aw"
  e   = "AQAB"
}
