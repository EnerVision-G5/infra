# Stockage Blob : un seul compte pour le projet, créé et durci par
# scripts/bootstrap.sh (pas de clé partagée, TLS 1.2, versions, corbeille),
# qui porte l'état Terraform et un conteneur par environnement et par usage.
#
# Pourquoi pas un compte par environnement : la stratégie de l'école plafonne
# à deux comptes par groupe de ressources, compteur tenu par une
# automatisation qui refuse ensuite toute création ou modification. Un compte,
# des conteneurs : la séparation entre environnements se fait au niveau du
# conteneur, y compris pour les droits (iam.tf).

data "azurerm_storage_account" "project" {
  name                = var.storage_account_name
  resource_group_name = data.azurerm_resource_group.this.name
}

# Nom préfixé par l'environnement : deux environnements sur le même compte ne
# peuvent pas se disputer un conteneur.
resource "azurerm_storage_container" "this" {
  for_each = toset(var.storage_containers)

  name                  = "${var.environment}-${each.value}"
  storage_account_id    = data.azurerm_storage_account.project.id
  container_access_type = "private"
}
