variable "subscription_id" {
  description = "Abonnement où vit cet environnement."
  type        = string
}

variable "resource_group_name" {
  description = "Groupe de ressources existant (fourni par l'école), écrit par scripts/bootstrap.sh."
  type        = string
}

variable "environment" {
  description = "Nom court de l'environnement, en minuscules (poc, dev, prod)."
  type        = string
}

variable "project" {
  type    = string
  default = "enervision"
}

variable "team" {
  description = "Courriel => { role = member | devops, object_id }."
  type = map(object({
    role      = string
    object_id = string
  }))
  default = {}
}

variable "storage_containers" {
  type    = list(string)
  default = []
}

variable "storage_blob_contributor_principal_ids" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
