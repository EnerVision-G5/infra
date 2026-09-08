# État de l'environnement PROD. Rien de secret : des noms, écrits par
# scripts/bootstrap.sh. Un environnement = une clé ; le compte est partagé.
terraform {
  backend "azurerm" {
    subscription_id      = "ca5c57dd-3aab-4628-a78c-978830d03bbd"
    resource_group_name  = "rg-MCharge2024_cours-projet-eadl"
    storage_account_name = "stenervisiontfca5c57"
    container_name       = "tfstate"
    key                  = "PROD.tfstate"
    use_azuread_auth     = true
  }
}
