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

variable "storage_account_name" {
  description = "Compte de stockage du projet (bootstrap)."
  type        = string
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

variable "blob_workloads" {
  description = "Identités applicatives : nom => rw | ro."
  type        = map(string)
  default     = {}
}

variable "workload_issuer_jwks" {
  description = "Clé publique de l'émetteur (scripts/issuer-keygen.sh)."
  type = object({
    kid = string
    n   = string
    e   = string
  })
  default = null
}
