# Droits, posés par Terraform : la liste des personnes et des identités qui
# accèdent à l'environnement est dans le code, relue en PR, appliquée par le
# lancement manuel. Ajouter quelqu'un, c'est une ligne dans <ENV>.auto.tfvars.

locals {
  # Conteneurs de cet environnement, plus celui de l'état pour les devops :
  # sans lui, pas de `terraform plan` en local.
  env_container_ids  = [for c in azurerm_storage_container.this : c.id]
  state_container_id = "${data.azurerm_storage_account.project.id}/blobServices/default/containers/tfstate"

  # Deux niveaux, comme viewer / editor sur un projet GCP.
  #   member : voit tout le groupe (Reader), lit les blobs de CET environnement.
  #   devops : le rôle Devops sur mesure de l'école sur le groupe, écrit les
  #            blobs de cet environnement et l'état Terraform.
  # Le groupe est commun à tous les environnements ; les blobs, non.
  team_group_roles = {
    member = ["Reader"]
    devops = ["Reader", var.devops_role_name]
  }
  team_blob_role = {
    member = "Storage Blob Data Reader"
    devops = "Storage Blob Data Contributor"
  }
  team_blob_scopes = {
    member = local.env_container_ids
    devops = concat(local.env_container_ids, [local.state_container_id])
  }

  team_group_assignments = flatten([
    for email, m in var.team : [
      for role in local.team_group_roles[m.role] : {
        key = "${email}/${role}", principal_id = m.object_id, role = role, scope = data.azurerm_resource_group.this.id
      }
    ]
  ])
  team_blob_assignments = flatten([
    for email, m in var.team : [
      for scope in local.team_blob_scopes[m.role] : {
        key = "${email}/${local.team_blob_role[m.role]}/${basename(scope)}", principal_id = m.object_id, role = local.team_blob_role[m.role], scope = scope
      }
    ]
  ])
}

# Le locataire de l'école n'autorise pas les groupes Entra ID : les droits
# vont à chaque personne, par son objectId. La personne qui tient le groupe
# n'est PAS dans la liste : ses rôles viennent de l'école et du bootstrap.
resource "azurerm_role_assignment" "team" {
  for_each = { for a in concat(local.team_group_assignments, local.team_blob_assignments) : a.key => a }

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = "User"
}

# Identités applicatives (identités managées, applications) : lecture et
# écriture des blobs de cet environnement, sans clé.
resource "azurerm_role_assignment" "apps" {
  for_each = {
    for pair in setproduct(var.storage_blob_contributor_principal_ids, local.env_container_ids) :
    "${pair[0]}/${basename(pair[1])}" => { principal_id = pair[0], scope = pair[1] }
  }

  scope                = each.value.scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
}

# --- Identités applicatives fédérées (workload_identity.tf)
# Même règle que pour les personnes : rw écrit, ro lit, sur les seuls conteneurs de cet environnement.
resource "azurerm_role_assignment" "workload" {
  for_each = {
    for pair in setproduct(keys(azurerm_user_assigned_identity.workload), local.env_container_ids) :
    "${pair[0]}/${basename(pair[1])}" => { name = pair[0], scope = pair[1] }
  }

  scope                = each.value.scope
  role_definition_name = var.blob_workloads[each.value.name] == "rw" ? "Storage Blob Data Contributor" : "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.workload[each.value.name].principal_id
  principal_type       = "ServicePrincipal"
}
