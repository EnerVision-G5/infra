# Inventaire

`ansible/inventories/on-premise/hosts.yml`

```yaml
all:
  children:
    application_servers:
      hosts:
        onpremise-server:
          ansible_host: "10.105.200.46"
          ansible_user: root
          ansible_port: 22
          ansible_password: "{{ vault_ansible_ssh_password }}"
```

| Champ | Valeur | Note |
|---|---|---|
| `ansible_host` | `10.105.200.46` | IP de la VM |
| `ansible_user` | `root` | connexion directe en root |
| `ansible_port` | `22` | SSH standard |
| `ansible_password` | `{{ vault_ansible_ssh_password }}` | **jamais en clair** — valeur dans le Vault |

## Groupes

- `all` → `provision.yml` (`hosts: all`)
- `application_servers` → `deploy.yml` (`hosts: application_servers`)

Un seul hôte aujourd'hui : `all` et `application_servers` désignent la même
machine.

## Prérequis poste de contrôle

- `ansible-core`, `ansible-lint`
- collections : `ansible-galaxy collection install -r ansible/requirements.yml`
  (`community.docker`, `community.general`)
- **`sshpass`** — obligatoire, l'authentification par mot de passe d'Ansible
  en dépend
- le mot de passe du Vault (voir [Secrets › Opérations](../secrets/operations.md))

## Configuration Ansible

`ansible.cfg` à la racine du dépôt :

```ini
[defaults]
roles_path = ./ansible/roles
inventory  = ./ansible/inventories/on-premise/hosts.yml
host_key_checking = False
```
