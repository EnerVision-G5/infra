# tflint : lint Terraform (variables inutilisées, types, conventions) et
# règles azurerm (SKU, régions, valeurs invalides) avant tout plan.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
