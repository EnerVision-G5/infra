# Droits de plan de données sur le compte de stockage, posés par Terraform :
# une identité listée lit et écrit les blobs, sans clé (storage.tf en refuse).
# Les personnes de l'équipe ne sont pas ici : elles tiennent leurs droits au
# niveau du groupe de ressources, comme l'école les donne (scripts/grant.sh).

resource "azurerm_role_assignment" "storage_blob_contributor" {
  for_each = toset(var.storage_blob_contributor_principal_ids)

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
