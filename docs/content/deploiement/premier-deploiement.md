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
  [Architecture › L'hôte](../architecture/hote.md). Vérifier :

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

## 7 — Seaux + clé Garage

DEUX seaux, et non un seul. `enervision-features` porte les partitions de
variables, que l'ETL réécrit à chaque run ; `enervision-datasets` porte
l'historique de référence, figé et irremplaçable. Les séparer est ce qui
garantit qu'un rejeu ne peut rien effacer d'une donnée que la chaîne ne sait
pas régénérer.

```bash
docker exec garage /garage key create enervision-app
docker exec garage /garage key info enervision-app --show-secret

for seau in enervision-features enervision-datasets; do
  docker exec garage /garage bucket create "$seau"
  docker exec garage /garage bucket allow --read --write --owner "$seau" --key <key-id>
done
```

Reporter l'`Access Key ID` et le `Secret Access Key` dans le Vault
(`vault_garage_s3_*`), étape 5.

## 7 bis — Historique de référence

Les CSV de référence — deux années horaires par site — ne sont ni dans le
dépôt `predict` ni dans l'image du collecteur. Rien ne les transporte : il
faut les déposer une fois dans `enervision-datasets`, sans quoi
`python -m collector.datasets` n'aura rien à charger et le premier
entraînement n'aura pas de saisons à apprendre.

Ils ne sont PAS copiés sur la VM. L'API S3 de Garage est routée par Traefik
sur `s3.enervision.com` : l'envoi part donc directement du poste qui détient
les fichiers, sans étape intermédiaire sur le serveur.

```bash
cd predict
export AWS_ENDPOINT_URL=http://s3.enervision.com
export AWS_ACCESS_KEY_ID=<key-id>              # étape 7
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_REGION=garage AWS_DEFAULT_REGION=garage

uv run python deploy/push-datasets.py datasets s3://enervision-datasets
```

`s3.enervision.com` doit résoudre vers l'IP de la VM, comme les autres noms
de l'étape 10 — même entrée dans le fichier `hosts` du poste.

Vérifier depuis le serveur :

```bash
docker exec garage /garage bucket info enervision-datasets    # 7 objets
```

Puis charger en base, une fois les applications déployées (étape 9) :

```bash
cd /opt/srv/applications/collector
docker compose run --rm --entrypoint python poller -m collector.datasets
```

Par `compose run` et non `docker run` : le service porte déjà le `.env` et
les DEUX réseaux nécessaires — `db_network` pour écrire dans `mesure`,
`storage_network` pour lire les CSV sur Garage. Un `docker run --network`
n'en attacherait qu'un.

Le chargement est rejouable : `sink.write` insère en `ON CONFLICT DO NOTHING`.
Il ne réécrit donc rien sur un serveur qui collecte déjà, il comble.

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
