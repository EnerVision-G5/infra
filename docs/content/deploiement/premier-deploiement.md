# Premier déploiement (VM neuve)

Checklist de bout en bout pour repartir de zéro.

## 1 — Poste de contrôle

```bash
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml
sudo apt install -y sshpass          # obligatoire (auth par mot de passe)
```

## 2 — Hôte

- VM accessible en SSH `root` sur le port 22.
- Docker présent, **`/etc/docker/daemon.json`** contenant `default-runtime:
  nvidia` **et** `features.containerd-snapshotter: false` — voir
  [runbook](../exploitation/docker-daemon.md). Vérifier :

    ```bash
    docker info | grep -iE "storage driver|default runtime"
    # -> overlay2 / nvidia
    ```

## 3 — DNS

Un enregistrement `A` par domaine, tous vers l'IP de la VM, + les wildcards
`*.s3` et `*.web`. Liste : [Architecture › Domaines](../architecture/domaines.md).

## 4 — Inventaire

`ansible/inventories/on-premise/hosts.yml` : mettre `ansible_host` sur l'IP de
la VM.

## 5 — Vault

```bash
ansible-vault edit ansible/inventories/on-premise/group_vars/all/vault.yml
```

Renseigner **tous** les `vault_*` requis :

| Clé | Produit par / format |
|---|---|
| `vault_ansible_ssh_password` | mot de passe SSH de la VM |
| `vault_timescaledb_password` | libre, fort |
| `vault_ghcr_username` / `vault_ghcr_token` | compte GitHub + PAT `read:packages` |
| `vault_garage_rpc_secret` | `openssl rand -hex 32` |
| `vault_garage_admin_token` / `vault_garage_metrics_token` | `openssl rand -hex 32` |
| `vault_monitoring_grafana_admin_password` | libre, fort |
| `vault_applications_api_secret_key` | `python -c "import secrets; print(secrets.token_urlsafe(48))"` (≥ 32) |
| `vault_garage_s3_access_key_id` / `vault_garage_s3_secret_access_key` | **après l'étape 7** (`garage key create`) |
| `vault_applications_mlflow_basic_auth_users` | `htpasswd -nbB <user> '<pass>'` |

## 6 — Provisionnement

```bash
ansible-playbook ansible/playbooks/provision.yml --ask-vault-pass
```

Vérifier : Traefik, Garage, TimescaleDB, la stack monitoring tournent.
Le layout Garage est appliqué automatiquement (`/garage status` doit montrer
le nœud avec une zone et une capacité).

## 7 — Bucket + clé Garage

```bash
docker exec garage /garage bucket create enervision-features
docker exec garage /garage key create enervision-app
docker exec garage /garage bucket allow --read --write --owner enervision-features --key <key-id>
docker exec garage /garage key info enervision-app --show-secret
```

Reporter l'`Access Key ID` et le `Secret Access Key` dans le Vault
(`vault_garage_s3_*`), étape 5.

Détail : [runbook layout Garage](../exploitation/garage-layout.md).

## 8 — Versions d'images

Dans `group_vars/all/vars.yml`, mettre chaque `applications_*_sha` sur un tag
`sha-<git>` réellement publié sur GHCR (sinon `docker pull` échoue).

## 9 — Déploiement applicatif

```bash
ansible-playbook ansible/playbooks/deploy.yml --ask-vault-pass
```

## 10 — Vérifications finales

```bash
docker ps --filter name=enervision- --format '{{.Names}}\t{{.Status}}'
```

| Endpoint | Attendu |
|---|---|
| `http://api.enervision.com/docs` | 200 (l'API a démarré, migrations appliquées) |
| `http://app.enervision.com/` | le dashboard, sans erreur de configuration |
| `http://app.enervision.com/config.js` | contient `API_BASE_URL` et `CSP_CONNECT_SRC` |
| `http://predict.enervision.com/health` | 200 (peut être `503` si aucun modèle promu — normal au début) |
| `http://grafana.enervision.com/` | login Grafana ; dashboard cAdvisor **rempli** |
| `http://garage.enervision.com/` | interface Garage |

## 11 — Premier modèle

`serving` répond `503` tant qu'aucun modèle n'est promu. Lancer un
entraînement et promouvoir :

```bash
systemctl start training.service
# quand le run est fini, lire ses métriques dans MLflow puis :
cd /opt/srv/applications/training
docker compose --project-name enervision-training --profile jobs \
  run --rm training --promote-version <n>
```
