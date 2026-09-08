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
