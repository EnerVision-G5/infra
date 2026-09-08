resource "azurerm_storage_account" "this" {
  # Ni tiret ni majuscule, 24 caractères maximum, unique au monde.
  name                = "st${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  access_tier              = "Hot"

  # Transport : TLS 1.2 minimum, HTTPS seulement.
  min_tls_version            = "TLS1_2"
  https_traffic_only_enabled = true

  # Aucun blob ni conteneur lisible anonymement, quoi que demande un conteneur.
  allow_nested_items_to_be_public = false

  # Pas de clé de compte : toute lecture ou écriture passe par une identité
  # Entra ID et un rôle (iam.tf). Une clé est un secret de plus à garder, à
  # faire tourner, et qui donne tout ; un rôle se retire.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  public_network_access_enabled = var.storage_public_network_access_enabled

  blob_properties {
    # Versions et corbeille : une suppression ou un écrasement se rattrape
    # pendant storage_soft_delete_days jours.
    versioning_enabled = true

    delete_retention_policy {
      days = var.storage_soft_delete_days
    }

    container_delete_retention_policy {
      days = var.storage_soft_delete_days
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.storage_containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
