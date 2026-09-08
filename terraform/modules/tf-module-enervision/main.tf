# Le groupe de ressources est fourni, pas créé : dans le locataire de l'école,
# chaque étudiant en reçoit un, avec un rôle qui ne permet pas d'en créer
# d'autres. C'est aussi la frontière des droits de la CI.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
      repository  = "EnerVision-G5/infra"
    },
    # Une stratégie de l'école refuse toute ressource sans l'étiquette `user`
    # égale à celle du groupe : elle est recopiée sur tout ce qui est créé.
    try({ user = data.azurerm_resource_group.this.tags["user"] }, {}),
    var.tags,
  )
}

# Suffixe stable (gardé dans l'état) pour les ressources dont le nom doit
# être unique au monde (compte de stockage).
resource "random_string" "suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}
