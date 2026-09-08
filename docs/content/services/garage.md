# Garage

Stockage objet compatible **S3**, mono-nœud. Sert les partitions de variables
de la chaîne predict et l'historique de référence. Expose aussi un endpoint web
(hébergement statique depuis un bucket) et une interface d'administration.

!!! note "MLflow n'utilise plus Garage"
    Les artefacts MLflow vont sur le volume local du rôle `mlflow` ou sur
    **Azure Blob** (`wasbs://`), plus sur Garage. Voir
    [Services › MLflow](mlflow.md).

| | |
|---|---|
| Rôle Ansible | `garage` (`provision.yml`) |
| Images | `dxflrs/garage:v2.0.0`, `khairul169/garage-webui:1.1.0` |
| Dossier hôte | `/opt/srv/garage/` (`compose.yml`, `.env`, `garage.toml`) |
| Réseaux | `storage_network`, `proxy_network` |
| Volumes | `garage_metadata`, `garage_data`, `garage_snapshots` |

## Ports internes

| Port | Usage |
|---|---|
| 3900 | API S3 (`s3.enervision.com`, `*.s3.enervision.com`) |
| 3901 | RPC inter-nœuds |
| 3902 | endpoint web (`web.enervision.com`, `*.web.enervision.com`) |
| 3903 | API admin (utilisée par `garage-webui`) |
| 3909 | interface `garage-webui` (`garage.enervision.com`) |

## `garage.toml`

```toml
db_engine = "sqlite"
replication_factor = 1
rpc_public_addr = "garage:3901"

[s3_api]   s3_region = "garage"   root_domain = ".s3.enervision.com"
[s3_web]   root_domain = ".web.enervision.com"   index = "index.html"
[admin]    # admin_token + metrics_token (Vault)
```

`.env` : `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN` (tous deux Vault).

## Bootstrap du layout

!!! danger "Sans layout appliqué, Garage répond 503 à tout"
    Un nœud neuf n'a **aucune capacité de stockage** tant que le layout n'est
    pas assigné puis appliqué.

Le rôle le fait automatiquement (idempotent, ne fait rien si le layout est
déjà en version ≥ 1) :

1. attend que `/garage status` réponde ;
2. si `Current cluster layout version: 0` → `layout assign -z dc1 -c 64G <node-id>` ;
3. `layout apply --version 1`.

La création du **bucket** et de la **clé S3** (lus par serving / training /
etl) reste manuelle, une fois : voir
[Premier déploiement](../deploiement/premier-deploiement.md), étape 7.

## Ce qui utilise Garage

| Client | Via | Bucket / usage |
|---|---|---|
| `etl` | S3 (`storage_network`) | écrit les partitions de variables (`s3://enervision-features`) |
| `serving` | S3 | relit ces partitions |
| `training` | S3 | apprend sur 90 j de partitions |

Les clients lisent les variables **`AWS_*`** (`AWS_ENDPOINT_URL` pointe le
conteneur, `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` produits par
`garage key create`, région `garage`).

## Endpoint web (`web.enervision.com`)

`<bucket>.web.enervision.com` sert le bucket `<bucket>` (avec un `index.html`).
`web.enervision.com` **tout court** ne correspond à aucun bucket → `404`
(c'est normal, ça veut dire que Garage tourne).

## Dépannage

| Symptôme | Cause |
|---|---|
| `503 Could not reach quorum of 1 (0 of 0)` | layout jamais appliqué — le rôle `garage` le corrige au prochain `provision.yml --tags garage` |
| `404` sur `web.enervision.com` | pas de bucket pour ce host — attendu |
| `403 AccessDenied` depuis un client S3 | mauvaise clé, ou région ≠ `garage` dans la signature SigV4 |
| interface webui vide | `API_ADMIN_KEY` ≠ `admin_token` du `garage.toml` |
