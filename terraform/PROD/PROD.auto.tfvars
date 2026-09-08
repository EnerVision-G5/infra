# Production. Idéalement dans un AUTRE groupe de ressources que DEV (celui
# d'un coéquipier : deux comptes de stockage au plus par groupe, et une
# production ne partage pas son périmètre avec le développement). Si le
# groupe change : resource_group_name ici, et le coéquipier qui le tient
# donne à l'identité CI id-enervision-github ses rôles dessus (voir README).
# subscription_id et resource_group_name sont écrits par scripts/bootstrap.sh
subscription_id     = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
resource_group_name = "rg-MCharge2024_cours-projet-eadl"
environment         = "prod"

# member : voit tout le groupe, lit les blobs
# devops : rôle Devops de l'école, écrit les blobs (état Terraform compris)
# object_id : az ad user show --id "prenom.nom@campus-eni.fr" --query id -o tsv
# Pas la personne qui tient le groupe (ses droits viennent de l'école)
team = {
  # "prenom.nom@campus-eni.fr" = { role = "devops", object_id = "00000000-0000-0000-0000-000000000000" }
  # "autre.nom@campus-eni.fr"  = { role = "member", object_id = "00000000-0000-0000-0000-000000000000" }
}

storage_containers = ["prod"]

# Identités (objectId) qui lisent et écrivent les blobs : applications, identités managées
storage_blob_contributor_principal_ids = []
