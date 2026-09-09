# Backup

Sauvegarde chiffrée hors-site de ce qui ne se reconstruit pas : la base, les
métadonnées et les données Garage, les journaux du monitoring. Outil
[restic](https://restic.net/), dépôt dans Azure Blob (`prod-data`, préfixe
`restic/`).

| | |
|---|---|
| Rôle Ansible | `backup` (`provision.yml`) |
| Image | `restic/restic:0.19.1` |
| Dossier hôte | `/opt/srv/backup/` — `backup.env`, `backup.secrets`, `issuer.pem`, `staging/` |
| Réseau | aucun réseau Docker dédié ; le conteneur restic sort vers Azure (443) |
| Volumes lus | `garage_garage_snapshots`, `garage_garage_data`, `monitoring_loki_data` (montés `:ro`) |
| Déclenchement | `backup-dump.timer` (02:00, dump local) → `backup.timer` (04:00, envoi Azure) → `backup-check.timer` (dimanche 05:00) |
| Ressources | 1 Go RAM, 1 CPU (`docker run --cpus/--memory`) |

## Deux temps

Le rôle sépare la préparation des artefacts de leur envoi :

| Phase | Unité · heure | Ce qu'elle fait | Réseau |
|---|---|---|---|
| **dump** | `backup-dump.service` · 02:00 | `pg_dump` + `pg_dumpall` dans `staging/`, `garage meta snapshot` | aucun |
| **upload** | `backup.service` · 04:00 | `restic backup` de `staging/` + volumes Garage + Loki, puis `restic forget --prune`, puis purge de `staging/` | Azure |
| **check** | `backup-check.service` · dim. 05:00 | `restic check` (structure du dépôt, sans relire les données) | Azure |

`enervision-backup backup` enchaîne dump puis upload — pour un lancement
manuel. Les deux phases prennent le **verrou partagé** `/run/enervision-jobs.lock`.

## Ce qui est sauvegardé

| Cible | Tag restic | Méthode |
|---|---|---|
| Base `enervision` | `db` | `pg_dump --format=custom --compress=0` + `pg_dumpall --globals-only` dans le conteneur `timescaledb`, écrits dans `staging/`, puis `restic backup` |
| Garage | `garage` | `garage meta snapshot` (copie cohérente de la base sqlite de métadonnées dans le volume `garage_snapshots`) puis `restic backup` de ce volume **et** des blocs de données (immuables, sûrs à chaud) |
| Journaux monitoring | `monitoring` | `restic backup` du volume `loki_data` (chunks + index Loki) |

Le dump base n'est **pas** compressé par `pg_dump` : restic déduplique mieux
sur du non-compressé, et compresse lui-même (`RESTIC_COMPRESSION=auto`).

## Chiffrement

restic chiffre **tout côté client** avant l'envoi (AES-256, MAC Poly1305) :
contenu, noms de fichiers, arborescence, métadonnées. Azure ne voit que des
blobs opaques. La clé du dépôt est `vault_backup_restic_password` — voir
[Points d'attention](#points-dattention).

## Configuration

`.env` généré (`/opt/srv/backup/backup.env`, `0600`) :

| Clé | Vient de |
|---|---|
| `RESTIC_REPOSITORY` | `azure:prod-data:/restic` (préfixe `restic/` du conteneur `prod-data`) |
| `RESTIC_PASSWORD` | `vault_backup_restic_password` |
| `AZURE_ACCOUNT_NAME` | `backup_azure_account_name` |
| `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` | `backup_azure_client_id` / `backup_azure_tenant_id` (`vars.yml`) |
| `AZURE_FEDERATED_TOKEN_FILE` | `/run/enervision-backup/federated-token.jwt` (écrit par le script) |

### Authentification Azure — sans secret côté Azure

La clé partagée du compte de stockage est désactivée : ni clé de compte, ni
SAS. Le script forge un JWT RS256 signé par la clé privée de l'émetteur
(`vault_workload_issuer_key`, la même que celle prévue pour l'API — voir
[Identités applicatives](https://github.com/EnerVision-G5/infra/blob/develop/terraform/docs/identites-applicatives.md)),
le régénère toutes les 4 minutes pendant le run, et restic l'échange
(`WorkloadIdentityCredential`) contre un accès Azure au nom de l'identité
managée `api-rw` (*Storage Blob Data Contributor* sur les conteneurs de
l'environnement, posé par Terraform).

## Rétention

`restic forget --group-by host,tags` après chaque sauvegarde, donc appliquée
**par cible** :

| Palier | Défaut | Variable |
|---|---|---|
| Quotidiennes | 7 | `backup_keep_daily` |
| Hebdomadaires | 1 | `backup_keep_weekly` |
| Mensuelles | 3 | `backup_keep_monthly` |
| Annuelles | 1 | `backup_keep_yearly` |

`--prune` dans le même passage (`backup_prune: true`) libère l'espace des
données déréférencées.

## Endpoints

Aucun. Rien n'est publié par Traefik, aucun port n'est ouvert. Les trois
unités sont des `oneshot` systemd sous le **verrou partagé**
`/run/enervision-jobs.lock` (une seule tâche lourde à la fois avec
l'entraînement, la dérive et les rattrapages).

## Logs et supervision

- **Dashboard** : Grafana → **Sauvegardes** (`enervision-sauvegardes`).
  Dernier run par phase, âge et nombre de snapshots par cible, taille du
  dépôt, durées, et les journaux en bas de page.
- **Métriques** : après chaque phase le script réécrit un fichier `.prom`
  dans `/var/lib/node_exporter/textfile` (`enervision-backup-<phase>.prom`),
  ramassé par le collecteur `textfile` de node-exporter. En cas d'échec au
  milieu d'une phase, le piège de sortie écrit quand même `success 0`.

  | Métrique | Portée |
  |---|---|
  | `enervision_backup_success{phase}` | 1 / 0 du dernier `dump` \| `upload` \| `check` |
  | `enervision_backup_duration_seconds{phase}` | durée de la dernière phase |
  | `enervision_backup_completion_timestamp_seconds{phase}` | fin de la dernière phase (epoch) |
  | `enervision_backup_snapshot_timestamp_seconds{tag}` | date du dernier snapshot par cible |
  | `enervision_backup_snapshots_count{tag}` | snapshots conservés par cible |
  | `enervision_backup_repository_size_bytes` | taille du dépôt (`restic stats --mode raw-data`) |
  | `enervision_backup_staging_bytes{artifact}` | taille des dumps locaux du dernier `dump` |

- **Échec** : le collecteur systemd de node-exporter suit
  `backup-dump.service`, `backup.service` et `backup-check.service` — une
  unité en échec apparaît dans Prometheus / Grafana comme les autres jobs.
- **Alerte** : *Sauvegarde hors-site trop ancienne* se déclenche si le
  dernier snapshot restic date de plus de 26 h, **ou** si la métrique
  n'existe pas du tout (`noDataState: Alerting`) — donc tant que la première
  sauvegarde n'a pas tourné.
- **Journaux** : promtail scrape le journal systemd de ces unités et les
  pousse dans Loki. Dans Grafana → Explore → source **Loki** :

  ```logql
  {unit="backup.service"}
  {unit=~"backup.*"} |= "=="
  {unit="backup-dump.service", level="err"}
  ```

  (labels `unit` et `level`, ce dernier depuis la priorité syslog).

## Opérations

```bash
# Lancer une sauvegarde complète à la demande (dump + envoi)
systemctl start backup-dump.service && systemctl start backup.service
journalctl -u backup-dump.service -u backup.service -f

# Juste rejouer l'envoi (le dump de 02:00 est encore dans staging/)
systemctl start backup.service

# Lister les snapshots (depuis la VM)
cd /opt/srv/backup
docker run --rm -i --env-file backup.env \
  -v /run/enervision-backup:/run/enervision-backup:ro \
  -v "$PWD/issuer.pem:$PWD/issuer.pem:ro" \
  restic/restic:0.19.1 snapshots
```

Le jeton fédéré n'existe que pendant une phase `upload` / `check` (le script
le crée et le purge). Pour une commande restic manuelle, générer un jeton
avec `terraform/scripts/workload-token.sh` dans
`/run/enervision-backup/federated-token.jwt`.

## Restauration

### Base

```bash
# 1. Récupérer le dernier dump
cd /opt/srv/backup
docker run --rm --env-file backup.env \
  -v /run/enervision-backup:/run/enervision-backup:ro \
  -v "$PWD/issuer.pem:$PWD/issuer.pem:ro" \
  -v /opt/srv/backup/restore:/restore \
  restic/restic:0.19.1 restore latest --tag db --target /restore

# 2. Restaurer dans une base vide (TimescaleDB : encadrer par les fonctions
#    pre/post_restore, sinon les hypertables reviennent incohérentes)
docker exec -e PGPASSWORD=… timescaledb \
  psql -U enervision -d enervision -c "SELECT timescaledb_pre_restore();"
docker exec -i -e PGPASSWORD=… timescaledb \
  pg_restore -U enervision -d enervision --no-owner --no-privileges \
  < /opt/srv/backup/restore/backup/db/enervision.dump
docker exec -e PGPASSWORD=… timescaledb \
  psql -U enervision -d enervision -c "SELECT timescaledb_post_restore();"
```

### Garage

Arrêter Garage, remplacer le contenu de `garage_metadata` par le snapshot
choisi (sous `garage/snapshots/<horodatage UTC>/`), remettre les blocs de
`garage/data/` si nécessaire, redémarrer. Détail :
[Recovering from failures](https://garagehq.deuxfleurs.fr/documentation/operations/recovering/).

### Journaux monitoring

`restic restore latest --tag monitoring --target /restore`, puis recopier
dans le volume `monitoring_loki_data` avec Loki arrêté.

## Points d'attention

!!! danger "La clé du dépôt ne vit pas que sur la VM"
    `vault_backup_restic_password` chiffre le dépôt. La perdre = perdre
    **toutes** les sauvegardes, définitivement. Elle doit être conservée
    aussi dans le gestionnaire de mots de passe de l'équipe, hors de la VM.

!!! note "Ordre de déploiement"
    Le rôle lit des volumes créés par `garage` et `monitoring`, et déclenche
    `garage meta snapshot`. Le premier `provision.yml` doit donc jouer ces
    rôles avant `backup` (c'est l'ordre du playbook). Le rôle `garage`
    définit `metadata_snapshots_dir` pour que les snapshots atterrissent
    dans le volume sauvegardé.

!!! note "L'identité `api-rw` doit exister côté Azure"
    `backup_azure_client_id` / `backup_azure_tenant_id` / `backup_workload_*`
    (`vars.yml`) pointent l'identité fédérée `api-rw` de PROD, créée par le
    `terraform apply` de PROD. Le rôle refuse de se déployer si ces variables
    sont vides.

!!! note "Dépôt dans `prod-data`, préfixe `restic/`"
    Faute de quota pour un conteneur dédié, le dépôt restic partage
    `prod-data` avec les blobs de l'API, sous le préfixe `restic/`
    (`backup_azure_prefix`). Le chiffrement restic isole le contenu ; ne pas
    supprimer `prod-data/restic/**` à la main.

!!! note "Un dump en clair vit ~2 h sur la VM"
    Entre `backup-dump` (02:00) et `backup` (04:00), le dump de la base est
    dans `/opt/srv/backup/staging/` (`0700`, root). La phase `upload` le
    purge une fois envoyé. Un `upload` qui échoue laisse donc le dump en
    place — c'est voulu, il sera repris au prochain passage.

## Dépannage

| Symptôme | Piste |
|---|---|
| `AADSTS700213` / `no matching federated identity` | `backup_workload_subject` ou `backup_workload_issuer` ne correspond pas à l'identifiant fédéré `api-rw` (Terraform) |
| `AADSTS700211` / erreur de signature | `backup_workload_kid` ou la clé privée ne sont pas ceux du JWKS publié ; cache Entra ID jusqu'à 1 h après une rotation |
| `AuthorizationPermissionMismatch` | l'identité `api-rw` n'a pas *Storage Blob Data Contributor* sur `prod-data` — vérifier `terraform apply` PROD |
| `Fatal: repository master key and config already initialized` sur `restic init` | normal si relancé — le script fait `restic cat config \|\| restic init` |
| `backup.service` tué à 90 s | `TimeoutStartSec` non pris en compte — vérifier que l'unité déployée est bien celle du rôle |
| `flock: … Temporary failure` | une autre tâche lourde tient `/run/enervision-jobs.lock` depuis plus d'une heure |
