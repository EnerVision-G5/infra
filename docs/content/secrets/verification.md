# Vérification

Deux garde-fous, tous deux dans le job CI `secrets` (`.github/workflows/ci.yml`)
et rejouables en local.

## `scripts/check-secrets.sh`

```bash
bash scripts/check-secrets.sh
```

Sortie non nulle = un secret potentiellement en clair. Ce qu'il teste :

| # | Contrôle |
|---|---|
| 1 | `vault.yml` existe et commence par `$ANSIBLE_VAULT` (donc chiffré) |
| 2 | chaque variable de `secret_vars` n'est définie, hors du Vault, **que** par indirection `clef: "{{ vault_… }}"` |
| 3 | aucun placeholder `A_REMPLACER` / `REMPLACER_<lettre>` dans les `.yml`, `.j2`, `.cfg`, `.env.example` suivis |
| 4 | `gitleaks detect` (si l'outil est présent) — arbre **et** historique Git |

`secret_vars` :

```
garage_rpc_secret · garage_admin_token · garage_metrics_token
postgres_password · ghcr_username · ghcr_token
monitoring_grafana_admin_password · applications_api_jwt_secret
mlflow_azure_connection_string · ansible_password
```

!!! note "Non couverts par le contrôle 2"
    `applications_predict_s3_*` utilise `| default('')` et **n'est pas** dans
    `secret_vars`. Le garder en indirection Vault reste la règle — gitleaks
    (contrôle 4) rattraperait une valeur en clair suffisamment entropique.

## gitleaks

Version `8.21.2`, installée dans le job CI. Scanne l'arbre et **tout
l'historique** (`fetch-depth: 0`).

### `.gitleaks.toml`

Règles par défaut conservées (`useDefault = true`), **une seule exception** :
les tags d'images `sha-<40 hexadécimaux>`. Ce sont des SHA de commits publics
(produits par `docker/metadata-action`), versionnés à dessein, mais qui ont
l'entropie d'une clé d'API et déclenchent la règle `generic-api-key`.
L'exception porte sur ce **motif seul**, pas sur les fichiers — `vars.yml`
reste scanné.

### `.gitleaksignore`

Deux empreintes, pour deux secrets Garage présents **uniquement dans
l'historique** (commit `d890a722`, ancien fichier `group_vars/all.yml`) :

```
d890a722…:ansible/inventories/on-premise/group_vars/all.yml:generic-api-key:11
d890a722…:ansible/inventories/on-premise/group_vars/all.yml:generic-api-key:18
```

!!! danger "Ces deux secrets sont compromis"
    `rpc_secret` et `admin_token` Garage : à **roter sur l'hôte**, puis
    reporter les nouvelles valeurs dans le Vault. Une purge d'historique
    (`git filter-repo` / BFG) reste recommandée si le dépôt sort de
    l'équipe.

## Ajouter une empreinte à `.gitleaksignore`

Quand un secret est retiré de l'arbre mais reste dans l'historique, copier la
ligne `Fingerprint:` exacte du rapport gitleaks rouge dans `.gitleaksignore`,
avec un commentaire (commit, quoi, statut de rotation).
