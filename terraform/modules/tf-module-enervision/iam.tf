# Droits, posés par Terraform : la liste des personnes et des identités qui
# accèdent à l'environnement est dans le code, relue en PR, appliquée par la
# CI. Ajouter quelqu'un, c'est une ligne dans <ENV>.auto.tfvars.

# --- L'équipe, sur le groupe de ressources ---------------------------------------
# Les coéquipiers reçoivent les rôles de var.team_roles : par défaut ceux
# que l'école donne à l'étudiant qui tient le groupe (son rôle « Devops »
# sur mesure, la lecture), plus l'accès aux blobs, état Terraform compris,
# ce que le rôle Devops ne couvre pas (plan de données).
#
# Le locataire de l'école n'autorise pas les groupes Entra ID : les droits
# vont donc à chaque personne, par son objectId. La personne qui tient le
# groupe n'est PAS dans la liste : ses rôles viennent de l'école et du
# bootstrap, Terraform refuserait de les recréer.
resource "azurerm_role_assignment" "team" {
  for_each = {
    for pair in setproduct(keys(var.team_members), var.team_roles) :
    "${pair[0]}/${pair[1]}" => { principal_id = var.team_members[pair[0]], role = pair[1] }
  }

  scope                = data.azurerm_resource_group.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = "User"
}

# --- Identités applicatives, sur le compte de stockage ----------------------------
# Une identité listée lit et écrit les blobs, sans clé (storage.tf en refuse).
resource "azurerm_role_assignment" "storage_blob_contributor" {
  for_each = toset(var.storage_blob_contributor_principal_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
