output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "storage_account_name" {
  value = data.azurerm_storage_account.project.name
}

output "blob_endpoint" {
  value = data.azurerm_storage_account.project.primary_blob_endpoint
}

output "storage_containers" {
  value = [for c in azurerm_storage_container.this : c.name]
}

output "workload_issuer" {
  description = "URL de l'émetteur de cet environnement (iss du jeton)."
  value       = local.workload_enabled ? local.issuer : null
}

output "workload_identities" {
  description = "Par identité applicative : client_id et sujet à présenter, à reporter dans le .env de l'API."
  value = {
    for name, id in azurerm_user_assigned_identity.workload : name => {
      client_id = id.client_id
      subject   = "${var.environment}/${name}"
      level     = var.blob_workloads[name]
    }
  }
}
