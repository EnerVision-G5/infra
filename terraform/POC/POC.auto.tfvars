# Valeurs de l'environnement POC. Versionné, rien de secret : c'est ce
# fichier qui dit ce que POC contient et où. subscription_id et
# resource_group_name sont écrits par scripts/bootstrap.sh.
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "poc"

storage_containers = ["poc"]

# Identités (objectId) qui lisent et écrivent les blobs : applications,
# identités managées. Les personnes : scripts/grant.sh.
storage_blob_contributor_principal_ids = []
