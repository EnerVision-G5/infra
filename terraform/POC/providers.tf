terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Aucun identifiant ici : en local la session `az login`, en CI le jeton OIDC
# (ARM_CLIENT_ID, ARM_TENANT_ID, ARM_USE_OIDC). L'abonnement vient du tfvars
# de l'environnement : c'est lui qui dit où cet environnement vit.
provider "azurerm" {
  subscription_id = var.subscription_id

  features {}

  # Les comptes de stockage du projet refusent les clés partagées : le
  # fournisseur parle au plan de données avec l'identité, comme tout le monde.
  storage_use_azuread = true
}
