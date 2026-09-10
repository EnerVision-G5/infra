# Rapport d'incident — `ml-stagiaire-03` (10.105.200.34)

**Date de l'incident :** mardi 8 septembre 2026
**Fenêtre concernée :** ~13 h 20 → 13 h 40 (heure locale / CEST) = ~11 h 20 → 11 h 40 UTC
**Analyse réalisée le :** 8 septembre 2026, ~14 h 05 CEST, en **lecture seule** (aucune modification effectuée — voir §9)
**Accès :** `ssh root@10.105.200.34`

> ⚠️ **Toutes les heures machine sont en UTC.** Le serveur est réglé sur `Etc/UTC` (`timedatectl` : horloge synchronisée, service NTP *inactive*).
> La France est en CEST (UTC+2) le 8/09/2026 : **heure locale = heure UTC + 2 h**.
> « 13 h 25 » côté utilisateur = **11 h 25 UTC** côté machine.

---

## 1. Résumé exécutif

1. Le conteneur a subi une **rafale d'écritures sur TimescaleDB** entre **11 h 25 et 11 h 28 UTC (13 h 25–13 h 28)**, puis a été **redémarré à 11 h 28 min 12 UTC (13 h 28)** ; il est revenu en service à **11 h 39 min 25 UTC (13 h 39)**.
2. Le redémarrage a été **propre et déclenché depuis l'extérieur du conteneur** (hyperviseur Proxmox, conteneur LXC n° 101). Ce **n'est pas un crash** : pas d'OOM, pas de kernel panic, pas de saturation CPU/RAM. C'est très probablement une **action d'exploitation** (quelqu'un a redémarré le CT pour couper l'emballement) ~3 min après le début de la rafale.
3. **Cause racine :** des **retraitements ETL / entraînement sur tout l'historique, lancés à la main** (`docker exec enervision-etl python -m etl --date 2024-12-31 --days 730`, `docker compose run --rm training --history-days 90/365 --promote`). Ces jobs réécrivent par `UPDATE` des **centaines de milliers de lignes** de la table `mesure`, ce qui fait « écrire à mort » TimescaleDB (WAL ×100) et publier en masse des *features* vers le stockage objet `garage`.
4. Le même jour, deux backfills massifs analogues avaient déjà eu lieu : **~49 000 lignes à 02 h 40 UTC** et **~126 000 lignes à 09 h 25–09 h 35 UTC (11 h 25–11 h 35)**. L'événement de 13 h 25 est le **troisième** de la série (celui-ci surtout en `UPDATE`, pas en `INSERT`).
5. **Facteur aggravant ponctuel :** la source de données amont `http://10.105.200.45:8000` a mis **~13 s** à répondre à 11 h 24 min 47 (13 h 24), faisant patiner le collecteur (`tick` de 0,8 s → 13,6 s) et grimper le compteur « pannes capteur ».
6. **Après le redémarrage**, un membre de l'équipe s'est connecté (console à 11 h 48, SSH depuis 10.105.200.37 à 11 h 49) et a **arrêté volontairement 3 conteneurs** : `enervision-mlflow`, `enervision-predict-cron`, `enervision-etl`. **Ils sont toujours arrêtés.**
7. **État à 12 h 14 UTC (14 h 14) :** hôte sain (charge 0,35 ; 4,9 Go RAM libres ; swap 0), TimescaleDB `healthy` avec checkpoints redevenus normaux, aucune requête lourde en cours.

---

## 2. Contexte système

| Élément | Valeur |
|---|---|
| Hôte | `ml-stagiaire-03`, Ubuntu 24.04.4 LTS |
| Virtualisation | Conteneur **LXC** sur **Proxmox** (noyau `6.8.12-9-pve`), disque `/dev/mapper/pve-vm--101--disk--0` → **VMID 101** |
| Ressources | RAM plafonnée à **8 Go** (48 vCPU visibles mais hôte partagé), disque `/` 63 Go utilisé à 45 % |
| Projet | **EnerVision « G5 »** — pipeline ML de prédiction de consommation énergétique (7 sites : SITE001…SITE007) |
| Base de données | `timescale/timescaledb:2.17.2-pg16`, base `enervision`, rôle `enervision`. Hypertable unique `mesure` (236 781 lignes, historique 2023-01-01 → 2026-09-08, 106 chunks) |
| Stack applicative | `enervision-{api, serving, front, etl, predict-cron, mlflow, collector-poller}` |
| Infra | `traefik`, `garage` (+ `garage-webui`) stockage objet S3, `grafana`, `prometheus`, `loki`, `promtail`, `cadvisor`, `node-exporter` |
| Ordonnancement des jobs | `enervision-etl` et `enervision-predict-cron` tournent en boucle shell : `sh -c 'while :; do <job> || echo …; sleep 3600; done'` (≈ 1 exécution / heure) |

---

## 3. Chronologie détaillée

| Heure UTC | Heure locale | Événement | Source |
|---|---|---|---|
| 08/09 ~09 h 22 | ~11 h 22 | (Re)déploiement de la stack `enervision-*` (conteneurs `Created 09:22:56–09:23:10`) | `docker ps` |
| 09 h 23 | 11 h 23 | 1ʳᵉ exécution ETL, `predict-cron` en échec (`ConnectError: All connection attempts failed`) | logs conteneurs |
| **09 h 25–09 h 35** | **11 h 25–11 h 35** | **Backfill massif : ~126 000 lignes insérées dans `mesure`** (event-time 2023 → 2026) | `mesure` par `inserted_at` |
| 10 h 21 min 47 | 12 h 21 | Session SSH `root` ouverte depuis **10.105.200.35** — **jamais refermée proprement** (tuée par le reboot) | `auth.log`, `last -x` |
| 11 h 00 → 11 h 20 | 13 h 00 → 13 h 20 | Système **calme** : CPU 94 % idle, charge 0,21, 0 swap, écritures disque ~120 Ko/s ; checkpoints Postgres toutes les 5 min, ~0,5 Mo de WAL | `sar` (dernier échantillon **11 h 20 min 25**) |
| **11 h 24 min 47** | **13 h 24** | Requête collecteur `GET 10.105.200.45:8000/.../SITE001/current` — **réponse au bout de ~13 s** | logs `collector-poller` |
| 11 h 25 min 01 | 13 h 25 | `tick` collecteur = **13,63 s** (normal : ~0,83 s) ; « pannes capteur : 12 ouverte(s) » ; retard données −13 s sur plusieurs sites | logs `collector-poller` |
| **11 h 25 min 26** | **13 h 25** | Postgres : `checkpoint starting: time` — ce checkpoint va accumuler **50 631 Ko de WAL** (×~100 vs baseline ~500 Ko) | logs `timescaledb` |
| **11 h 26 min 00** | **13 h 26** | Pic cAdvisor : `enervision-etl` CPU **0,58 cœur** / RSS **262 Mo** (vs 3 Mo) / réseau entrant **653 Ko/s** ; `timescaledb` écritures disque **1,83 Mo/s** / réseau entrant **486 Ko/s** ; `garage` écritures **99 Ko/s** (vs 0,3 Ko/s) | Prometheus/cAdvisor |
| 11 h 26–11 h 28 | 13 h 26–13 h 28 | Charge hôte montée à **0,70** (sur 48 vCPU) — **aucune saturation**, pas d'OOM, pas de swap | Prometheus `node_load1` |
| **11 h 28 min 12** | **13 h 28** | **Arrêt du conteneur** : `postgres received fast shutdown request` ; `sshd Received signal 15` ; arrêt systemd **ordonné** ; `Journal stopped` à 11 h 28 min 23 | logs `timescaledb`, journald |
| 11 h 28 → 11 h 39 | 13 h 28 → 13 h 39 | Conteneur **arrêté (~11 min)** | `last -x` |
| **11 h 39 min 25** | **13 h 39** | **Redémarrage** ; la stack repart (`restart=unless-stopped`) | journald, `docker inspect` |
| 11 h 39–11 h 40 | 13 h 39–13 h 40 | ETL exécute son cycle **normal** `--days 2` | logs `enervision-etl` |
| 11 h 47–11 h 48 | 13 h 47–13 h 48 | Connexions **console** (`/dev/lxc/tty1`), plusieurs **échecs de mot de passe**, puis `ROOT LOGIN` à 11 h 48 min 31 | journald |
| 11 h 49 min 37 | 13 h 49 | Session **SSH `root` depuis 10.105.200.37** | `auth.log` |
| 11 h 49 min 57 | 13 h 49 | `docker stop enervision-mlflow` (exit 0) | journald + historique shell |
| 11 h 51 min 01 | 13 h 51 | `docker stop enervision-predict-cron` → SIGTERM ignoré, **SIGKILL après 10 s**, exit 137 | journald |
| 11 h 51 min 20 | 13 h 51 | `docker stop enervision-etl` → idem, exit 137 | journald |

---

## 4. Preuves, par source

### 4.1 `sar` / métriques hôte (boot précédent)
Dernier échantillon **11 h 20 min 25 UTC** (le suivant, 11 h 30 min 25, n'a jamais été pris à cause du reboot → **trou de mesure `sar` sur 11 h 20 – 11 h 28**, exactement la fenêtre de l'incident).
Jusqu'à 11 h 20 min 25 : `%idle` 93,9 ; `ldavg-1` 0,21 ; `pswpin/out` 0 ; `bwrtn/s` ~120 Ko/s. **Rien d'anormal côté hôte.**

### 4.2 Prometheus / cAdvisor (données conservées, survécu au reboot) — valeurs au **11 h 26 min 00**
| Métrique | Baseline | Pic 11 h 26 |
|---|---|---|
| `enervision-etl` CPU | ~0 | **0,58 cœur** |
| `enervision-etl` RSS | 3 Mo | **262 Mo** (limite 512 Mo) |
| `enervision-etl` réseau entrant | ~0 | **653 Ko/s** |
| `timescaledb` écritures disque | 10–48 Ko/s | **1,83 Mo/s** |
| `timescaledb` réseau entrant | ~0,4 Ko/s | **486 Ko/s** |
| `timescaledb` CPU | 0,006 cœur | 0,126 cœur |
| `garage` écritures disque | 0,31 Ko/s | **99 Ko/s** |
| `node_load1` | 0,15 | 0,70 |

> Le pic est **attribué au conteneur `enervision-etl`** par cgroup, alors que **`docker logs enervision-etl` ne montre rien** entre 11 h 25 et 11 h 40 → l'activité vient d'un **`docker exec` dans ce conteneur** (sa sortie ne va pas dans `docker logs`), pas de la boucle horaire.

### 4.3 Logs TimescaleDB (checkpoints)
```
11:00–11:20  checkpoint toutes les 5 min : write 8–13 s, 83–128 buffers (0.1–0.2 %), distance 486–589 kB
11:25:26     checkpoint starting: time
11:28:12.385 LOG: received fast shutdown request
11:28:12.515 checkpoint complete: wrote 3018 buffers (4.6 %); distance = 50631 kB   ← ×~100
```

### 4.4 Collecteur (`enervision-collector-poller`)
`tick` 11 h 23 min 48 = 0,83 s → **`tick` 11 h 25 min 01 = 13,63 s** → `tick` 11 h 25 min 48 = 0,84 s.
Cause du pic : réponse lente (~13 s) de `http://10.105.200.45:8000` (source amont). `retard données` jusqu'à −13,4 s, `data_quality` `critical/partial` sur plusieurs sites.
11 h 28 min 12 : `signal 15 reçu, arrêt après le tick en cours` — 70 ticks exécutés.

### 4.5 Nature du redémarrage
- `auth.log` 11 h 00 – 11 h 28 : **uniquement** des sessions CRON `root` (`debian-sa1`). **Aucun `sudo`, aucun `reboot`, aucune ouverture/fermeture de session SSH** dans cette fenêtre.
- Arrêt systemd **ordonné** (services stoppés dans l'ordre, `postfix terminating on signal 15`, `sshd Received signal 15`).
- ⇒ redémarrage **déclenché hors du conteneur** : très probablement `pct reboot 101` / interface Proxmox. **Non vérifiable depuis l'intérieur du conteneur** — à confirmer sur l'hyperviseur (`/var/log/pve/tasks/`, historique HA).

### 4.6 Base `enervision` (lecture seule)
- **180 352 lignes** insérées dans `mesure` le 8/09, event-time **2023-01-01 → 2026-09-08** (réécriture d'historique complet).
- Répartition des insertions du jour par tranche de 5 min :
  - fond ~35 / 5 min (collecteur normal : 7 sites)
  - **02 h 40–02 h 50 UTC : ~48 800 lignes**
  - **09 h 25–09 h 35 UTC : ~126 500 lignes** (rafale principale)
  - **11 h 20–11 h 28 UTC : normal (~7 / min)** → l'événement de 13 h 25 **n'a pas inséré en masse** ; il était **`UPDATE`-lourd** (ré-imputation) + lecture (job `training`).
- `quality_source` : **236 382 lignes `etl`** / 399 `source` → l'ETL a (ré)imputé **quasiment toute la table**. `imputation_method` : `none` 144 480, `locf` 70 024, `interpolation` 21 878.
- `pg_stat_user_tables` : `_hyper_1_1_chunk` (chunk le plus ancien) → `n_tup_ins` 88 037 / **`n_tup_upd` 361 051**. Les autres chunks : 1176 ins / 1176 upd (1 seul `UPDATE` par ligne). → **les réécritures répétées martèlent surtout les vieux chunks**.
- `pg_stat_activity` (actuel) : **aucune** requête active. `pg_stat_statements` : **non installé**.

### 4.7 Historique shell `root` (`/root/.bash_history`, fichier partagé par les sessions .33/.35/.37)
Commandes révélatrices (dans l'ordre) :
```
docker exec enervision-etl python -m etl --days 7
docker compose --project-name enervision-training --profile jobs run --rm training --history-days 90  --promote
docker exec enervision-etl python -m etl --date 2024-12-31 --days 730
docker compose --project-name enervision-training --profile jobs run --rm training --until 2024-12-31 --history-days 365 --promote
...
docker exec -it timescaledb psql -U enervision -d enervision
docker stop enervision-mlflow
docker stop enervision-predict-cron
docker stop enervision-etl
```
Également : débogage d'un **MLflow qui renvoie 403** derrière traefik (problème d'`--allowed-hosts` / en-tête `Host: mlflow.enervision.com`) — **sujet distinct**, sans lien avec l'emballement.

---

## 5. Analyse — cause racine

**L'« emballement de l'ETL » et le « TimescaleDB qui écrit à mort » que vous voyez dans Grafana sont réels**, mais ne correspondent pas à une dérive spontanée d'un service : ce sont les effets de **retraitements sur tout l'historique lancés manuellement** (`etl --days 730`, `training --history-days 365 --promote`).

Mécanisme :
1. L'ETL, sur une plage de dates large, **relit puis ré-impute** les mesures et **réécrit** `consumption_kw_imputed`, `imputation_method`, `data_quality`, `quality_source`, `null_reasons`.
2. Comme la table `mesure` n'a **pas de colonne `updated_at`** ni de garde d'idempotence, chaque passe fait un `UPDATE` de **toutes** les lignes de la plage (→ 236 k lignes sur 237 k portent aujourd'hui `quality_source='etl'`, et le chunk 2023 a pris 361 k `UPDATE`).
3. Ces `UPDATE` massifs génèrent énormément de **WAL** (50 Mo en 3 min contre ~0,5 Mo/5 min), d'où le pic d'écritures disque TimescaleDB, et l'ETL **republie les features** vers `garage` (pic d'écritures objet).
4. Sur cet hôte **8 Go**, l'impact reste **I/O et bruit applicatif** : la charge n'est montée qu'à 0,7/48, **pas d'OOM, pas de swap**. Le **redémarrage de 13 h 28 est une décision humaine/exploitation** (couper l'emballement), pas une conséquence technique inévitable.
5. **Déclencheur temporel du pic de 13 h 25 :** la lenteur (~13 s) de la source `10.105.200.45:8000` a fait patiner le collecteur au même moment ; la coïncidence (job manuel + collecteur en retard + checkpoint Postgres) donne la « bosse » nette visible à 13 h 25–13 h 28.

**Série de la journée :** 02 h 40 UTC (~49 k lignes, *sans* session interactive → job planifié ou conteneur qui rejoue au démarrage), 09 h 25–09 h 35 UTC (~126 k lignes, au redéploiement de 09 h 22), **11 h 25–11 h 28 UTC (13 h 25 — l'incident signalé)**.

---

## 6. État actuel (constaté à 12 h 14 UTC / 14 h 14)

| | |
|---|---|
| Hôte | `up 34 min`, charge **0,35 / 0,29 / 0,39**, **4,9 Go RAM libres** / 8 Go, **swap 0** |
| TimescaleDB | `healthy`, checkpoints redevenus normaux, **aucune requête active** |
| Conteneurs **actifs et sains** | `timescaledb`, `enervision-api`, `enervision-serving`, `enervision-front`, `enervision-collector-poller`, `grafana`, `prometheus`, `loki`, `promtail`, `cadvisor`, `node-exporter`, `traefik`, `garage`, `garage-webui` |
| Conteneurs **arrêtés volontairement** (11 h 49–11 h 51) | **`enervision-etl`**, **`enervision-predict-cron`**, **`enervision-mlflow`** |
| Conséquence | Tant qu'ils sont arrêtés : **pas d'ETL horaire**, **pas de rafraîchissement des prédictions**, **MLflow indisponible**. Le collecteur, lui, continue d'alimenter `mesure` (7 lignes/min). |

---

## 7. Constats secondaires

1. **Wrapper d'ordonnancement fragile** : `sh -c 'while :; do … ; sleep 3600; done'` ne relaie pas `SIGTERM` → tout `docker stop` attend 10 s puis `SIGKILL` (exit 137). Cosmétique mais brouille le diagnostic (137 ≠ OOM ici).
2. **ETL non idempotent** : réécriture systématique de toute la plage, pas de borne ni de détection de changement.
3. **`mesure`** : clé primaire `(site_id, ts)`, pas d'`updated_at`, pas de compression de chunks activée → chaque backfill = churn complet + WAL massif.
4. **Pression mémoire récurrente** : les 7 et 8/09 (boots précédents), un healthcheck conteneur a répété `procReady not received (possibly OOM-killed)` (Sep 7 19 h 05 → Sep 8 08 h 43). Hôte 8 Go, `enervision-mlflow` seul plafonné à 2 Go et collé au plafond.
5. **NTP `inactive`** (horloge synchronisée quand même, mais à surveiller).
6. **`pg_stat_statements` non installé** → analyse forensique limitée (pas de top requêtes).
7. **`psql -U postgres`** échoue (`role "postgres" does not exist`) — le rôle est `enervision`.
8. **MLflow 403** derrière traefik (`--allowed-hosts` / `Host`) — problème ouvert, non lié.
9. **Source amont `10.105.200.45:8000`** : latence ponctuelle ~13 s absorbée sans timeout ni backoff court côté collecteur.

---

## 8. Recommandations

**Court terme**
1. Décider avec l'équipe du redémarrage des 3 conteneurs stoppés (ils ont été arrêtés **exprès**) :
   `docker start enervision-mlflow enervision-predict-cron enervision-etl`
2. **Interdire les retraitements « full history » en journée** sur cet hôte : `--days 730` / `--history-days 365` uniquement en fenêtre calme, **une seule instance à la fois**.
3. Côté hyperviseur : confirmer qui/quoi a redémarré le **CT 101** à 11 h 28 UTC (`/var/log/pve/tasks/`, `pct config 101`, HA).

**Moyen terme**
4. Rendre l'ETL **incrémental / idempotent** : borne de dates stricte, ou colonne `updated_at` + `UPDATE … WHERE valeurs distinctes`, pour ne pas réécrire toute la table à chaque passe.
5. Remplacer le `while/sleep` par un vrai ordonnanceur (systemd timer / cron) avec `exec` + `trap` → arrêt propre, plus de `SIGKILL`.
6. TimescaleDB : augmenter `max_wal_size` / `checkpoint_timeout`, envisager la **compression de chunks** anciens ; superviser `container_fs_writes_bytes_total{name="timescaledb"}` et la taille du WAL, avec alerte.
7. Installer **`pg_stat_statements`** (`shared_preload_libraries`) pour la prochaine fois.
8. Collecteur : **timeout court + backoff** sur `10.105.200.45:8000`.
9. `timedatectl set-ntp true`.
10. Revoir les limites mémoire des conteneurs vs les 8 Go de l'hôte (mlflow 2 Go, etc.).

---

## 9. Périmètre de l'intervention — aucune modification

Toutes les commandes exécutées sur `10.105.200.34` étaient en **lecture seule** :
- `hostname`, `date`, `uptime`, `free`, `timedatectl`, `who`, `last`, `id`
- `journalctl …` (lecture), `grep` sur `/var/log/auth.log*`, `sar -f /var/log/sysstat/…`
- `docker ps / inspect / logs / stats / port / system df` (aucun `run`, `restart`, `stop`, `start`, `rm`, `exec` d'écriture)
- `docker exec prometheus wget -qO- http://localhost:9090/api/v1/…` (API de requête HTTP GET)
- `docker exec timescaledb psql -U enervision -d enervision` : **uniquement des `SELECT` / `\d`** (aucun `INSERT/UPDATE/DELETE/DDL`)
- lecture de `/root/.bash_history`

Aucun fichier, service, conteneur, configuration ou donnée n'a été créé, modifié ou supprimé sur le serveur.

---

## 10. Annexes

Fichiers bruts dans `./annexes/` :

| Fichier | Contenu |
|---|---|
| `journald_boot-precedent_arret-11h28.txt` | journald du boot précédent (séquence d'arrêt 11 h 28) + grep OOM/panic |
| `logs-conteneurs_11h20-11h28.txt` | logs `collector-poller`, `api`, `serving` sur la fenêtre + ports + journald post-reboot 11 h 45–11 h 55 |
| `prometheus-cadvisor_11h08-11h30.txt` | séries Prometheus/cAdvisor (CPU, RSS, I/O disque, réseau) par conteneur sur l'incident |
| `timescaledb-checkpoints_+_historique-shell.txt` | checkpoints TimescaleDB 11 h 00–11 h 28 + `/root/.bash_history` |
| `db-mesure_stats.txt` | schéma `mesure`, tailles de tables, `pg_stat_user_tables`, répartition `inserted_at`, `quality_source` |
| `authlog_sessions_+_etat-actuel.txt` | `auth.log` 10 h 15–11 h 30, sessions SSH, `docker stats`, santé des conteneurs, état actuel |
