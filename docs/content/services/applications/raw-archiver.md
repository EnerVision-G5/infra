# raw-archiver

Consomme `energy.data.raw`, tamponne les mesures et les écrit en **Parquet** sur
**Azure Blob** (`<container>/raw/dt=AAAA-MM-JJ/…parquet`). Archive brute, à côté
de l'ingestion en base. Deuxième maillon de la chaîne événementielle.

| | |
|---|---|
| `kind` | `worker` (processus long, sans port ni route) |
| Dépôt | `raw-archiver` |
| Image | `ghcr.io/enervision-g5/raw-archiver:{{ applications_raw_archiver_sha }}` |
| Conteneur | `enervision-raw-archiver` |
| Réseaux | `broker_network` (Kafka) — Azure Blob est joint en HTTPS sortant |
| Volume | `issuer.pem` (clé privée de l'émetteur) monté en lecture seule |
| Ressources | 384 Mo RAM, 0.5 CPU |
| Durcissement | `read_only`, `tmpfs /tmp`, `no-new-privileges` |

## Accès Azure sans clé de compte

Le service **ne porte aucun secret Azure**. Il signe un JWT court (RS256) avec
la **clé privée de l'émetteur de l'environnement** ; Entra ID l'échange contre
l'identité managée **`api-rw`** (droit *Storage Blob Data Contributor* sur le
conteneur). Mécanisme complet : `terraform/docs/identites-applicatives.md`.

Le rôle `applications` dépose `issuer.pem` (0600, depuis le Vault) dans
`/opt/srv/applications/raw-archiver/` et le monte sur
`{{ applications_workload_key_path_in_container }}`.

## Configuration (`raw-archiver.env.j2`)

| Clé | Variable Ansible | Source |
|---|---|---|
| `KAFKA_BOOTSTRAP_SERVERS` / `KAFKA_TOPIC` / `KAFKA_GROUP_ID` | `applications_raw_archiver_kafka_*` | défauts du rôle |
| `BLOB_ACCOUNT_URL` | `applications_blob_account_url` | `terraform output blob_endpoint` |
| `BLOB_CONTAINER` | `applications_blob_container` | `terraform output storage_containers` (`dev-data`) |
| `BLOB_PREFIX` | `applications_raw_archiver_blob_prefix` | `raw` |
| `AZURE_TENANT_ID` | `applications_azure_tenant_id` | `az account show --query tenantId` |
| `AZURE_CLIENT_ID` | `applications_raw_archiver_azure_client_id` | `terraform output workload_identities` → `api-rw.client_id` |
| `WORKLOAD_ISSUER` | `applications_workload_issuer` | `terraform output workload_issuer` |
| `WORKLOAD_SUBJECT` | `applications_raw_archiver_workload_subject` | `dev/api-rw` |
| `WORKLOAD_KID` | `applications_workload_kid` | `.kid` à côté de la clé (`dev-20260908`) |
| `WORKLOAD_KEY_FILE` | *(chemin dans le conteneur)* | défaut du rôle |
| `FLUSH_INTERVAL_SECONDS` / `FLUSH_MAX_ROWS` | `applications_raw_archiver_flush_*` | 300 s / 5000 lignes |

Le rôle **refuse de déployer** si `applications_workload_key` (la clé privée)
est absente, encore un placeholder, ou si un des identifiants Azure manque.

## Dépannage

| Symptôme | Piste |
|---|---|
| crash au démarrage, `AuthorizationPermissionMismatch` | identité `api-ro` au lieu de `api-rw`, ou rôle Terraform pas appliqué |
| `AADSTS700213` / `AADSTS700211` | `sub` / `iss` / `kid` ne correspondent pas au JWKS publié, ou cache Entra ID (jusqu'à 1 h) |
| `Clé privée de l'émetteur introuvable` | `issuer.pem` pas monté — vérifier le Vault et le redéploiement |
| aucun blob écrit | pas de message dans `energy.data.raw`, ou buffer pas encore flushé (`FLUSH_*`) |
| `ClientAuthenticationError` HTTPS | la VM n'a pas d'accès sortant vers `*.blob.core.windows.net` |
