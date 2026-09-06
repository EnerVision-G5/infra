# Opérations Vault

Fichier : `ansible/inventories/on-premise/group_vars/all/vault.yml`

## Consulter / éditer

```bash
ansible-vault view ansible/inventories/on-premise/group_vars/all/vault.yml
ansible-vault edit ansible/inventories/on-premise/group_vars/all/vault.yml
```

## Fournir le mot de passe du Vault

Le mot de passe **n'est jamais commité**. Trois options, par ordre de
préférence :

| Option | Commande |
|---|---|
| interactif | `ansible-playbook … --ask-vault-pass` |
| fichier local hors Git | `echo 'MDP' > .vault_pass && chmod 600 .vault_pass` puis `--vault-password-file .vault_pass` |
| variable d'environnement | `export ANSIBLE_VAULT_PASSWORD_FILE=~/.config/enervision/vault-pass` |

`.gitignore` couvre `.vault_pass*` et `vault_pass*`.

En CI, le mot de passe vient du secret GitHub `ANSIBLE_VAULT_PASSWORD`
(*Settings → Secrets and variables → Actions*). Optionnel : sans lui,
`ansible-lint` et `--syntax-check` passent quand même (avec un avertissement
de déchiffrement).

## Ajouter un secret

Trois endroits, dans cet ordre :

1. **`vault.yml`** — déclarer `vault_<nom>: <valeur>` (`ansible-vault edit`).
2. **`vars.yml`** — rattacher : `<nom>: "{{ vault_<nom> }}"`, dans le bloc
   « Rattachement des secrets » en bas de fichier.
3. **`scripts/check-secrets.sh`** — ajouter `<nom>` au tableau `secret_vars`
   pour que le contrôle « défini uniquement par indirection Vault »
   s'applique.

Puis consommer `<nom>` dans un rôle / template — jamais `vault_<nom>`
directement.

## Roter un secret

```bash
ansible-vault edit …/vault.yml          # remplacer la valeur
ansible-playbook ansible/playbooks/<playbook>.yml --tags <role> --ask-vault-pass
```

Le rôle régénère le `.env` / la config concernée et redéploie le conteneur.
Certains secrets exigent une action côté service en plus (ex. changer
`GRAFANA_ADMIN_PASSWORD` ne réinitialise pas un mot de passe déjà stocké dans
`grafana_data` : il faut soit repartir du volume, soit changer le mot de passe depuis l'interface Grafana).

## Changer le mot de passe du Vault lui-même

```bash
ansible-vault rekey ansible/inventories/on-premise/group_vars/all/vault.yml
```

Puis mettre à jour le secret GitHub `ANSIBLE_VAULT_PASSWORD` et les copies
locales.

## Secrets compromis dans l'historique

Deux secrets Garage ont fuité dans un commit ancien (`d890a722`, avant la
sécurisation Vault) et sont recensés dans `.gitleaksignore`. Ils sont
**considérés comme compromis** : à roter sur l'hôte (`rpc_secret` +
`admin_token`). Voir [Vérification](verification.md).
