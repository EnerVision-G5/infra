# Identités applicatives : comment une API on-premise accède aux blobs sans
# aucun secret côté Azure.
#
# Le locataire de l'école interdit les app registrations. Une identité
# managée, elle, est permise, et accepte des identifiants fédérés de
# n'importe quel émetteur OpenID Connect : l'API présente un jeton signé par
# NOTRE émetteur, Azure l'échange contre l'identité. C'est le mécanisme que
# la CI utilise déjà avec GitHub comme émetteur.
#
# L'émetteur, c'est une paire de clés par environnement : la clé privée reste
# on-premise (vault Ansible, jamais dans Terraform ni dans l'état), la clé
# publique arrive ici (workload_issuer_jwks) et Terraform publie les deux
# documents qu'Azure vient lire : la découverte et le JWKS, servis par le
# site statique du compte du projet, à https://<compte>.web.../<env>/.
#
# Une identité par niveau de droit (blob_workloads), pas par API : moins de
# clés à gérer, et un sujet distinct par identité.

locals {
  workload_enabled = var.workload_issuer_jwks != null && length(var.blob_workloads) > 0

  # L'URL d'émetteur porte l'environnement : une clé compromise en dev ne
  # signe rien pour prod.
  issuer = "${trimsuffix(data.azurerm_storage_account.project.primary_web_endpoint, "/")}/${var.environment}"

  discovery_document = {
    issuer                                = local.issuer
    jwks_uri                              = "${local.issuer}/jwks.json"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
  }

  # Conteneur $web, créé par l'activation du site statique (bootstrap).
  web_container_id = "${data.azurerm_storage_account.project.id}/blobServices/default/containers/$web"

  jwks_document = {
    keys = local.workload_enabled ? [merge(var.workload_issuer_jwks, { kty = "RSA", use = "sig", alg = "RS256" })] : []
  }
}

# --- Documents de l'émetteur, sur le site statique ($web)
resource "azurerm_storage_blob" "openid_configuration" {
  count = local.workload_enabled ? 1 : 0

  name                 = "${var.environment}/.well-known/openid-configuration"
  storage_container_id = local.web_container_id
  type                 = "Block"
  content_type         = "application/json"
  source_content       = jsonencode(local.discovery_document)
}

resource "azurerm_storage_blob" "jwks" {
  count = local.workload_enabled ? 1 : 0

  name                 = "${var.environment}/jwks.json"
  storage_container_id = local.web_container_id
  type                 = "Block"
  content_type         = "application/json"
  source_content       = jsonencode(local.jwks_document)
}

# --- Une identité managée par niveau
resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workload_enabled ? var.blob_workloads : {}

  name                = "id-${var.project}-${var.environment}-${each.key}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags
}

# Sujet = <env>/<nom> : l'API doit présenter exactement celui-là.
resource "azurerm_federated_identity_credential" "workload" {
  for_each = azurerm_user_assigned_identity.workload

  name                = "issuer-${var.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
  parent_id           = each.value.id
  issuer              = local.issuer
  subject             = "${var.environment}/${each.key}"
  audience            = ["api://AzureADTokenExchange"]

  depends_on = [azurerm_storage_blob.openid_configuration, azurerm_storage_blob.jwks]
}
