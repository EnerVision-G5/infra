# Secrets

Modèle de gestion : Vault chiffré + indirection dans vars.yml.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- vault.yml (chiffré) sous des noms vault_*, vars.yml qui fait pointer les variables métier dessus
- Table : variable métier ↔ clé Vault ↔ rôle qui la consomme
- Rien de sensible en clair dans le dépôt
