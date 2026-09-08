module "enervision" {
  source = "../modules/tf-module-enervision"

  resource_group_name = var.resource_group_name
  project             = var.project
  environment         = var.environment
  tags                = var.tags

  team = var.team

  storage_account_name                   = var.storage_account_name
  storage_containers                     = var.storage_containers
  storage_blob_contributor_principal_ids = var.storage_blob_contributor_principal_ids
}
