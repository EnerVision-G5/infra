# Secrets

Aucune valeur sensible n'est en clair dans le dépôt. Le modèle :

```
group_vars/all/
├── vars.yml     ← variables non sensibles + rattachement  clef: "{{ vault_clef }}"
└── vault.yml    ← chiffré avec ansible-vault  ($ANSIBLE_VAULT en tête)
```

Les rôles et templates ne référencent que des variables **métier**
(`ghcr_token`, `timescaledb_password`, …). `vars.yml` les fait pointer, par
indirection, vers des clés `vault_*` définies dans `vault.yml` chiffré.

Un seul endroit porte la valeur réelle ; `git` ne voit jamais rien en clair ;
et [`check-secrets.sh`](verification.md) le vérifie en CI.

## Table : variable métier → clé Vault → consommateur

| Variable métier | Clé Vault | Consommée par |
|---|---|---|
| `ansible_password` | `vault_ansible_ssh_password` | connexion SSH (`hosts.yml`) |
| `timescaledb_password` | `vault_timescaledb_password` | timescaledb, api, collector, etl, training, predict-cron |
| `ghcr_username` | `vault_ghcr_username` | rôle `applications` — `docker login ghcr.io` |
| `ghcr_token` | `vault_ghcr_token` | idem (PAT `read:packages`) |
| `garage_rpc_secret` | `vault_garage_rpc_secret` | garage (`garage.toml`, `.env`) |
| `garage_admin_token` | `vault_garage_admin_token` | garage + garage-webui |
| `garage_metrics_token` | `vault_garage_metrics_token` | garage (endpoint métriques) |
| `monitoring_grafana_admin_password` | `vault_monitoring_grafana_admin_password` | grafana |
| `applications_api_jwt_secret` | `vault_applications_api_secret_key` | api — `JWT_SECRET` (≥ 32 caractères) |
| `applications_predict_s3_access_key_id` | `vault_garage_s3_access_key_id` | serving, training, etl |
| `applications_predict_s3_secret_access_key` | `vault_garage_s3_secret_access_key` | serving, training, etl |
| `applications_mlflow_basic_auth_users` | `vault_applications_mlflow_basic_auth_users` | mlflow (si exposé) — format htpasswd |

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
