# L'hôte

La machine qui porte tout, et les contraintes qui en découlent.

## Caractéristiques

| | |
|---|---|
| Type | VM sous Proxmox (noyau `*-pve`) |
| Accès | SSH `root` sur le port **22**, **authentification par mot de passe** (valeur dans le Vault, cf. [Secrets](../secrets/index.md)) |
| Adresse | `10.105.200.46` (inventaire : [Référence › Inventaire](../reference/inventaire.md)) |
| GPU | carte NVIDIA — `nvidia-container-runtime` est le **runtime Docker par défaut** |
| Docker | driver de stockage **overlay2** (voir plus bas) |

`sshpass` est nécessaire sur le poste de contrôle pour qu'Ansible se connecte
en mot de passe.

## Fournie provisionnée

La VM est livrée avec Docker installé et configuré, le GPU opérationnel et le
durcissement système déjà fait. Les rôles Ansible qui faisaient ce travail
(`base`, `ssh`, `firewall`, `security`, `docker_engine`) **ont été retirés**.

`provision.yml` ne garde de l'ancien rôle `docker_engine` qu'une chose : la
**création des réseaux Docker partagés**, en `pre_tasks`.

## `/etc/docker/daemon.json` — géré à la main

!!! warning "Ne pas laisser Ansible réécrire ce fichier"
    Il porte deux réglages **indispensables et non gérés par le dépôt** :

    ```json
    {
      "default-runtime": "nvidia",
      "runtimes": { "nvidia": { "args": [], "path": "nvidia-container-runtime" } },
      "features": { "containerd-snapshotter": false }
    }
    ```

    - `default-runtime: nvidia` — sans lui, aucun conteneur ne voit le GPU.
    - `features.containerd-snapshotter: false` — repasse Docker sur le driver
      **overlay2**. Sans lui, Docker utilise le magasin d'images containerd,
      que **cAdvisor ne sait pas lire** : les dashboards conteneurs restent
      vides.

    Si le fichier existe déjà, **fusionner** ces clés sans écraser la config
    nvidia, puis `systemctl restart docker`. Contrôle :

    ```
    docker info | grep -iE "storage driver|default runtime"
    #   Storage Driver: overlay2
    #   Default Runtime: nvidia
    ```

    Un changement de driver de stockage rend l'ancien magasin d'images
    invisible : re-tirer les images ensuite (rejouer `provision.yml` puis
    `deploy.yml`). Les volumes de données ne sont pas concernés.

## Répertoires sur l'hôte

| Chemin | Contenu |
|---|---|
| `/opt/srv/traefik/` | compose + `.env` de Traefik |
| `/opt/srv/garage/` | compose + `.env` + `garage.toml` |
| `/opt/srv/postgres/` | compose + `.env` |
| `/opt/srv/kafka/` | compose + `.env` |
| `/opt/srv/mlflow/` | `Dockerfile` + compose + `.env` |
| `/opt/srv/monitoring/` | compose + `.env` + configs Prometheus/Loki/Promtail/Grafana |
| `/opt/srv/applications/<name>/` | un dossier par application : `compose.yml`, `.env`, `.sha` |

Tous ces fichiers sont **générés** — la source est dans `ansible/roles/`.

## Ports publiés sur l'hôte

Volontairement rares : presque tout passe par les réseaux Docker.

| Port | Service | Portée |
|---|---|---|
| `80`, `443` | Traefik | public |
| `127.0.0.1:5432` | PostgreSQL | loopback (admin `psql`) |
| `127.0.0.1:8081` | pgweb | loopback (tunnel SSH — temporaire) |
| `127.0.0.1:8080` | kafka-ui | loopback (tunnel SSH — temporaire) |
| `127.0.0.1:5000` | MLflow | loopback (tunnel SSH) |

Voir [Référence › Réseaux & ports](../reference/reseaux-ports.md).
