# Valeurs de l'environnement POC. Versionné, rien de secret : c'est ce
# fichier qui dit ce que POC contient et où. subscription_id et
# resource_group_name sont écrits par scripts/bootstrap.sh.
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "poc"

# Coéquipiers : nom lisible => objectId Entra ID, obtenu par
#   az ad user show --id prenom.nom@campus-eni.fr --query id -o tsv
# Ils reçoivent Reader, Devops-cours-projet-eadl et Storage Blob Data
# Contributor sur le groupe. Pas la personne qui tient le groupe.
team_members = {
  # "prenom-nom" = "00000000-0000-0000-0000-000000000000"
}

storage_containers = ["poc"]

# Identités (objectId) qui lisent et écrivent les blobs : applications,
# identités managées. Les personnes : scripts/grant.sh.
storage_blob_contributor_principal_ids = []
