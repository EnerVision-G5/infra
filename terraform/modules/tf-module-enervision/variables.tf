# --- Commun ---------------------------------------------------------------------

variable "resource_group_name" {
  description = "Groupe de ressources existant où tout est créé."
  type        = string
}

variable "project" {
  type    = string
  default = "enervision"
}

variable "environment" {
  description = "Nom court de l'environnement, en minuscules (poc, dev, prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.environment))
    error_message = "environment : 2 à 6 caractères parmi [a-z0-9]."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- storage.tf -----------------------------------------------------------------

variable "storage_containers" {
  description = "Conteneurs Blob du compte de stockage, tous privés."
  type        = list(string)
  default     = []
}

variable "storage_replication_type" {
  description = "Standard_LRS est la seule réplication autorisée par l'école ; ZRS ou GRS ailleurs."
  type        = string
  default     = "LRS"
}

variable "storage_soft_delete_days" {
  description = "Rétention des blobs et conteneurs supprimés, en jours (1 à 365)."
  type        = number
  default     = 7
}

variable "storage_public_network_access_enabled" {
  description = "Accès réseau public au compte, filtré par l'authentification seule. À fermer en production (point de terminaison privé)."
  type        = bool
  default     = true
}

# --- iam.tf ---------------------------------------------------------------------

variable "team" {
  description = "L'équipe : courriel => { role = member | devops, object_id = objectId Entra ID (az ad user show --id <courriel> --query id -o tsv) }. Sans la personne qui tient le groupe."
  type = map(object({
    role      = string
    object_id = string
  }))
  default = {}

  validation {
    condition     = alltrue([for m in values(var.team) : contains(["member", "devops"], m.role)])
    error_message = "team : role doit valoir member ou devops."
  }
}

variable "team_role_bundles" {
  description = "Rôles Azure derrière chaque niveau : member voit tout et lit les blobs ; devops a le rôle Devops de l'école et écrit les blobs, état Terraform compris."
  type        = map(list(string))
  default = {
    member = ["Reader", "Storage Blob Data Reader"]
    devops = ["Reader", "Devops-cours-projet-eadl", "Storage Blob Data Contributor"]
  }
}

variable "storage_blob_contributor_principal_ids" {
  description = "Identités (objectId) autorisées à lire et écrire les blobs du compte : applications, identités managées. Les personnes reçoivent leurs droits au niveau du groupe, par scripts/grant.sh."
  type        = list(string)
  default     = []
}
