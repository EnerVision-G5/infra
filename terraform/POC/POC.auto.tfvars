# Valeurs de l'environnement POC. Versionné, rien de secret : c'est ce
# fichier qui dit ce que POC contient et où. subscription_id et
# resource_group_name sont écrits par scripts/bootstrap.sh.
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "poc"

# L'équipe, comme les membres d'un projet GCP. Deux niveaux :
#   member : voit tout le groupe, lit les blobs ;
#   devops : rôle Devops de l'école, écrit les blobs (état Terraform compris).
# object_id : az ad user show --id <courriel> --query id -o tsv
# Pas la personne qui tient le groupe (ses droits viennent de l'école).
team = {
  # "prenom.nom@campus-eni.fr" = { role = "devops", object_id = "00000000-0000-0000-0000-000000000000" }
  # "autre.nom@campus-eni.fr"  = { role = "member", object_id = "00000000-0000-0000-0000-000000000000" }
}

storage_containers = ["poc"]

# Identités (objectId) qui lisent et écrivent les blobs : applications,
# identités managées. Les personnes : scripts/grant.sh.
storage_blob_contributor_principal_ids = []
