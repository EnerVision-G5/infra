# Racine Terraform du projet EnerVision (IaC, ADR-011).
#
# Ce fichier ne provisionne encore rien : il fixe seulement les contraintes de
# version pour que `terraform fmt`, `terraform init` et `terraform validate`
# aient une configuration à valider dès la mise en place de la CI (EV-02).
# Les ressources Azure (Static Web Apps, inférence ML, Key Vault) et la
# description des deux environnements arrivent avec les tickets d'infra dédiés.

terraform {
  required_version = ">= 1.9"
}
