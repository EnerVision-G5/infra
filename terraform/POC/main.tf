# Environnement POC : ce qui existe sur Azure pour lui. Le pendant d'un
# inventaire Ansible : un appel du module projet, avec les valeurs de
# l'environnement. Les briques elles-mêmes sont dans modules/tf-module-enervision.

module "enervision" {
  source = "../modules/tf-module-enervision"

  resource_group_name = var.resource_group_name
  project             = var.project
  environment         = var.environment
  tags                = var.tags

  team = var.team

  storage_containers                     = var.storage_containers
  storage_blob_contributor_principal_ids = var.storage_blob_contributor_principal_ids
}
