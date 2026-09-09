# Monitoring

Stack observabilité : **métriques** (Prometheus + exporters) et **logs**
(Promtail → Loki), le tout visualisé dans **Grafana**.

| | |
|---|---|
| Rôle Ansible | `monitoring` (`provision.yml`) |
| Dossier hôte | `/opt/srv/monitoring/` |
| Réseau | `monitoring_network` (+ `proxy_network` pour Grafana) |

## Composants

| Conteneur | Image | Rôle |
|---|---|---|
| `grafana` | `grafana/grafana:11.4.0` | visualisation, seul exposé (`grafana.enervision.com`) |
| `prometheus` | `prom/prometheus:v3.1.0` | métriques, rétention **15 j** |
| `loki` | `grafana/loki:3.3.2` | logs, rétention **168 h** (7 j), stockage filesystem |
| `promtail` | `grafana/promtail:3.3.2` | découvre les conteneurs par le socket Docker, pousse vers Loki |
| `node-exporter` | `prom/node-exporter:v1.8.2` | métriques hôte (CPU, RAM, disque, réseau) |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:v0.52.1` | métriques **par conteneur** |

Volumes : `grafana_data`, `prometheus_data`, `loki_data`, `promtail_data`.

## Métriques — Prometheus

Cibles scrapées (`prometheus.yml`, intervalle 15 s) :

```
prometheus       localhost:9090
node-exporter    node-exporter:9100
cadvisor         cadvisor:8080
traefik          traefik:8082
```

## Logs — Promtail → Loki

Promtail a deux sources :

- `docker_sd_configs` (socket Docker) : **tous** les conteneurs, labels
  `container`, `stream`, `compose_project` ;
- `journal` : le journal systemd de l'hôte, **filtré** sur les unités des
  traitements datés (`training`, `drift`, `collector-backfill`,
  `etl-backfill`, `backup`, `backup-dump`, `backup-check`) — leurs `oneshot`
  ne sont pas des conteneurs. Labels `unit`, `level`. Promtail tourne en
  `root` et monte `/var/log/journal` + `/run/log/journal` + `/etc/machine-id`
  en lecture seule.

Requête type dans Grafana → Explore → source **Loki** :

```logql
{container="enervision-api"}
{compose_project="enervision-serving"} |= "ERROR"
{unit=~"backup.*"}
{unit="training.service", level="err"}
```

Le volume `loki_data` (chunks + index) est sauvegardé quotidiennement vers
Azure Blob par le rôle [`backup`](backup.md). `prometheus_data` et
`grafana_data`, eux, ne le sont pas : séries jetables et provisioning
regénéré.

## Grafana

- Auth : `admin` / mot de passe Vault (`GF_SECURITY_ADMIN_PASSWORD`).
  Inscription désactivée.
- **Datasources provisionnées** (UID fixes) : `Prometheus` (défaut), `Loki`.
- **Dashboards provisionnés**, lus depuis des fichiers, **non modifiables**
  depuis l'UI :

    | Dashboard | ID Grafana.com |
    |---|---|
    | Node Exporter Full | 1860 |
    | cAdvisor | 21743 |
    | Traefik | 17346 |

## Alertes

Provisionnées comme les dashboards, dans `provisioning/alerting/` — donc
**non modifiables depuis l'UI**, et perdues si on les édite là.

**Aucun point de contact.** Les alertes s'allument dans Grafana et ne
notifient personne : la VM n'a pas de relais sortant vérifié, et une alerte
qui échoue à partir est pire qu'une alerte qu'on sait devoir aller regarder.
Ajouter un webhook plus tard ne touche que ce fichier.

Deux groupes, et le second est la vraie nouveauté.

| Alerte | Source | Se déclenche quand |
|---|---|---|
| Mémoire de la VM | Prometheus | moins de 15 % disponible, 10 min |
| Conteneur près de son plafond | Prometheus | > 90 % de SON plafond, 10 min |
| Traitement daté en échec | Prometheus | une unité systemd `failed`, 5 min |
| L'ETL ne publie aucune variable | Loki | 2 cycles à `0 heure(s) publiée(s)` |
| Aucune prédiction archivée | Loki | `Tous les sites ont échoué` |
| La collecte n'écrit plus | Loki | aucun `tick :` depuis 2 h |

Le groupe `capacite` interroge Prometheus : il voit la **machine**. Le groupe
`chaine` interroge Loki : il voit la **chaîne**. Cette seconde famille existe
parce qu'aucune métrique ne dit « l'ETL publie zéro heure » ou « les sept
sites ont échoué » — ces pannes ne vivent que dans les journaux, et elles y
sont restées cinq jours sans que personne ne les voie. Loki et promtail
étaient déjà là ; il ne manquait que la question.

Chaque règle porte une annotation `runbook` : la commande exacte à taper,
lisible depuis l'alerte elle-même.

`node-exporter` porte désormais `--collector.systemd` et le montage de
`/run/systemd/private`. Sans ce montage il démarre, ne remonte aucune unité,
et ne le dit qu'en DEBUG — une supervision muette qui a l'air en place.

## Reprise automatique

Les traitements datés (`training`, `drift`, `collector-backfill`,
`etl-backfill`) rejouent **une seule fois** après un échec, un quart d'heure
plus tard (`Restart=on-failure`, `RestartSec`, `StartLimitBurst=2`). Un job
tué à son plafond mémoire échouerait de la même façon en repartant aussitôt ;
un quart d'heure plus tard, la machine peut avoir rendu ce qui manquait.
Au-delà, l'unité reste en échec — et l'alerte « traitement daté en échec » le
dit.

!!! warning "`drift` ne rejoue jamais sur le code 2"
    `RestartPreventExitStatus=2` : le code 2 est un **verdict** — dérive
    constatée — pas une panne. Le rejouer ne changerait rien à ce qu'il a
    mesuré, et masquerait ce qu'il annonce.

Les services longs, eux, sont en `restart: unless-stopped` : un kill par le
cgroup les fait repartir seuls.

Enfin, chaque conteneur porte un `oom_score_adj` qui décide **qui meurt en
premier** si la VM manque de mémoire, plutôt que de laisser le noyau choisir
au score — c'est-à-dire souvent le plus gros, donc la base :

| `oom_score_adj` | Conteneurs |
|---|---|
| −500 | `timescaledb`, `traefik` |
| −200 | `enervision-api`, `enervision-serving` |
| +300 | `enervision-mlflow` |
| +500 | `front`, `collector-poller`, `etl`, `predict-cron` |
| +800 | `training`, `drift` |

## Points d'attention

!!! warning "cAdvisor dépend du driver de stockage Docker et de sa version"
    - Sous le magasin d'images **containerd** (`docker info` →
      `Storage Driver: overlayfs`), cAdvisor n'énumère **aucun conteneur**.
      Le réglage `containerd-snapshotter: false` de `/etc/docker/daemon.json`
      l'évite — voir [Architecture › L'hôte](../architecture/hote.md).
    - cAdvisor doit être en **≥ `v0.52.1`** : les versions antérieures
      parlent une API Docker trop ancienne pour le démon de la VM et
      n'affichent aucune métadonnée conteneur.

- Loki rejette les entrées de plus de 168 h (`reject_old_samples`) — sans
  effet en collecte au fil de l'eau.
- `node-exporter` tourne en `pid: host` avec `/:/host:ro` — normal, il lit
  l'hôte.
- Datasources et dashboards sont **provisionnés depuis des fichiers** (UID
  fixes, lecture seule) : une modification faite dans l'UI Grafana est
  perdue au prochain rechargement.
