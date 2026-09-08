# Droits, posés par Terraform : la liste des personnes et des identités qui
# accèdent à l'environnement est dans le code, relue en PR, appliquée par la
# CI. Ajouter quelqu'un, c'est une ligne dans <ENV>.auto.tfvars.

# --- L'équipe, sur le groupe de ressources ---------------------------------------
# Deux niveaux, comme viewer / editor sur un projet GCP : `member` voit tout
# et lit les blobs ; `devops` a le rôle Devops sur mesure de l'école (celui
# de l'étudiant qui tient le groupe) et écrit les blobs, état Terraform
# compris. La correspondance niveau → rôles Azure est dans team_role_bundles.
#
# Le locataire de l'école n'autorise pas les groupes Entra ID : les droits
# vont donc à chaque personne, par son objectId. La personne qui tient le
# groupe n'est PAS dans la liste : ses rôles viennent de l'école et du
# bootstrap, Terraform refuserait de les recréer.
resource "azurerm_role_assignment" "team" {
  for_each = {
    for pair in flatten([
      for email, m in var.team : [
        for role in var.team_role_bundles[m.role] : { email = email, object_id = m.object_id, role = role }
      ]
    ]) : "${pair.email}/${pair.role}" => pair
  }

  scope                = data.azurerm_resource_group.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.object_id
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
