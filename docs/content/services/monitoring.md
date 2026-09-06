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

Promtail utilise `docker_sd_configs` (socket Docker) : il découvre **tous**
les conteneurs et pousse leurs logs à Loki avec les labels `container`,
`stream`, `compose_project`.

Requête type dans Grafana → Explore → source **Loki** :

```logql
{container="enervision-api"}
{compose_project="enervision-serving"} |= "ERROR"
```

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

## Points d'attention

!!! warning "cAdvisor dépend du driver de stockage Docker"
    Sous le magasin d'images **containerd** (snapshotter `overlayfs`),
    cAdvisor n'énumère **aucun conteneur** : les panneaux Docker restent
    vides. Le fix est `containerd-snapshotter: false` dans
    `/etc/docker/daemon.json` — voir le
    [runbook `/etc/docker/daemon.json`](../exploitation/docker-daemon.md).

- Loki rejette les entrées de plus de 168 h (`reject_old_samples`) — sans
  effet en collecte au fil de l'eau.
- `node-exporter` tourne en `pid: host` avec `/:/host:ro` — normal, il lit
  l'hôte.

## Dépannage

Voir le [runbook monitoring en panne](../exploitation/monitoring-depannage.md) :
cAdvisor vide, Promtail muet, target Prometheus `down`.

```bash
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | python3 -m json.tool
docker logs promtail --tail 30
docker exec cadvisor wget -qO- http://localhost:8080/healthz
```
