# --- Commun

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

# --- storage.tf

variable "storage_account_name" {
  description = "Compte de stockage du projet, créé par scripts/bootstrap.sh : il porte l'état et les conteneurs de tous les environnements."
  type        = string
}

variable "storage_containers" {
  description = "Conteneurs de cet environnement, préfixés par son nom (dev-data, prod-data…). Tous privés."
  type        = list(string)
  default     = []
}

# --- iam.tf

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

variable "project_roles" {
  description = "Pose les rôles de niveau groupe (Reader, rôle Devops) et l'accès à l'état Terraform pour les membres de team. Ces rôles sont par groupe de ressources, pas par environnement : un seul environnement du groupe doit l'activer, celui du bootstrap. Les autres ne posent que les rôles sur leurs conteneurs."
  type        = bool
  default     = false
}

variable "devops_role_name" {
  description = "Rôle Azure du niveau devops sur le groupe : celui que l'école donne à l'étudiant qui tient le groupe. Contributor dans un abonnement à soi."
  type        = string
  default     = "Devops-cours-projet-eadl"
}

variable "storage_blob_contributor_principal_ids" {
  description = "Identités (objectId) autorisées à lire et écrire les blobs de cet environnement : applications, identités managées. Les personnes, elles, sont dans team."
  type        = list(string)
  default     = []
}

# --- workload_identity.tf

variable "blob_workloads" {
  description = "Identités applicatives de l'environnement : nom => niveau (rw : lit et écrit les blobs de l'environnement ; ro : lit). Une par niveau suffit, les API d'un même niveau partagent la clé."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for lvl in values(var.blob_workloads) : contains(["rw", "ro"], lvl)])
    error_message = "blob_workloads : niveau rw ou ro."
  }
}

variable "workload_issuer_jwks" {
  description = "Clé PUBLIQUE de l'émetteur de l'environnement (scripts/issuer-keygen.sh) : kid, n, e. Null : aucune identité applicative."
  type = object({
    kid = string
    n   = string
    e   = string
  })
  default = null
}
