# Secrets

Aucune valeur sensible n'est en clair dans le dépôt. Le modèle :

```
group_vars/all/
├── vars.yml     ← variables non sensibles + rattachement  clef: "{{ vault_clef }}"
└── vault.yml    ← chiffré avec ansible-vault  ($ANSIBLE_VAULT en tête)
```

Les rôles et templates ne référencent que des variables **métier**
(`ghcr_token`, `postgres_password`, …). `vars.yml` les fait pointer, par
indirection, vers des clés `vault_*` définies dans `vault.yml` chiffré.

Un seul endroit porte la valeur réelle ; `git` ne voit jamais rien en clair ;
et [`check-secrets.sh`](verification.md) le vérifie en CI.

## Table : variable métier → clé Vault → consommateur

| Variable métier | Clé Vault | Consommée par |
|---|---|---|
| `ansible_password` | `vault_ansible_ssh_password` | connexion SSH (`hosts.yml`) |
| `postgres_password` | `vault_postgres_password` | postgres, api |
| `ghcr_username` | `vault_ghcr_username` | rôle `applications` — `docker login ghcr.io` |
| `ghcr_token` | `vault_ghcr_token` | idem (PAT `read:packages`) |
| `garage_rpc_secret` | `vault_garage_rpc_secret` | garage (`garage.toml`, `.env`) |
| `garage_admin_token` | `vault_garage_admin_token` | garage + garage-webui |
| `garage_metrics_token` | `vault_garage_metrics_token` | garage (endpoint métriques) |
| `monitoring_grafana_admin_password` | `vault_monitoring_grafana_admin_password` | grafana |
| `applications_api_jwt_secret` | `vault_applications_api_secret_key` | api — `JWT_SECRET` (≥ 32 caractères) |
| `vault_garage_s3_access_key_id` / `_secret_access_key` | *(dans le vault)* | plus de consommateur — serving / training / etl retirés ; reviendront avec la nouvelle chaîne ML |
| `mlflow_azure_connection_string` | `vault_mlflow_azure_connection_string` | mlflow — seulement si artefacts sur Azure Blob (`wasbs://`) |
| `applications_workload_key` | `vault_workload_issuer_key` | raw-archiver — clé privée PEM de l'émetteur d'identités applicatives (`issuer-keygen.sh`) |

!!! note "Nom de clé historique"
    `applications_api_jwt_secret` pointe `vault_applications_api_secret_key`
    (ancien nom) : la clé Vault a gardé son nom pour ne pas rechiffrer le
    fichier lors d'un renommage.

## Ce qui n'est pas un secret

Le `.env` du **front** (`front.env.j2`) ne porte que des adresses de service :
elles sont republiées en clair dans `/config.js`, lisible par quiconque ouvre
la page. **Ne jamais y mettre de secret.**

## Suite

- [Opérations Vault](operations.md) — éditer, roter, ajouter un secret
- [Vérification](verification.md) — `check-secrets.sh` et gitleaks
