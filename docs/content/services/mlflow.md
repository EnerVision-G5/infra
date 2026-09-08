# MLflow

Registre de modèles et journal des entraînements. Pivot de la chaîne ML :
`training` y enregistre ses versions, `serving` y résout l'alias du modèle
qu'il sert. Sans lui, `serving` démarre et refuse les prévisions en 503.

| | |
|---|---|
| Rôle Ansible | `mlflow` (`provision.yml`) |
| Image | construite sur place — `FROM ghcr.io/mlflow/mlflow:v3.1.1` + `azure-storage-blob`, `azure-identity` |
| Dossier hôte | `/opt/srv/mlflow/` (`Dockerfile`, `compose.yml`, `.env`) |
| Réseau | `ml_network` uniquement |
| Volume | `mlflow_data` → `/mlflow` (backend SQLite + artefacts si destination locale) |
| Port publié | `127.0.0.1:5000` (tunnel SSH) |
| Ressources | 2 Go RAM, 1 CPU |

## Image construite sur place

L'image officielle MLflow ne tire pas le client de stockage Azure. Le rôle
génère un `Dockerfile` (`FROM {{ mlflow_base_image }}` + `pip install
azure-storage-blob azure-identity`) et déploie avec `build: policy` : l'image
`enervision-mlflow:local` est construite si elle manque. Après un changement de
`mlflow_base_image`, rejouer en forçant la reconstruction :

```
ansible-playbook provision.yml --tags mlflow --vault-password-file .vault_pass
docker compose -f /opt/srv/mlflow/compose.yml build --no-cache   # sur l'hôte, si besoin
```

## Configuration (ligne de commande)

Le serveur se règle dans son `compose.yml`, pas par un `.env` :

| Option | Variable | Défaut |
|---|---|---|
| `--backend-store-uri` | `mlflow_backend_store_uri` | `sqlite:////mlflow/mlflow.db` |
| `--artifacts-destination` | `mlflow_artifacts_destination` | `/mlflow/artifacts` (volume local) |
| `--allowed-hosts` | `mlflow_allowed_hosts` | `mlflow:5000,localhost:5000,127.0.0.1:5000` |
| `--serve-artifacts` | *(toujours)* | le serveur relaie les artefacts en proxy |

!!! note "MLflow 3 et l'en-tête Host"
    MLflow 3 rejette tout en-tête `Host` non listé dans `--allowed-hosts`
    (protection contre le DNS rebinding), **y compris venant de ses propres
    clients**. `serving` et `training` joignent `http://mlflow:5000` : cet hôte
    doit rester dans la liste.

## Artefacts

Par défaut, sur le volume local `mlflow_data`. Pour les basculer sur **Azure
Blob** :

1. un conteneur de blob existe (Terraform : ajouter `mlflow` à
   `storage_containers`, ou `az storage container create`) ;
2. `mlflow_artifacts_destination: "wasbs://<conteneur>@<compte>.blob.core.windows.net"`
   dans `group_vars` ;
3. la chaîne de connexion au Vault sous `vault_mlflow_azure_connection_string`.

Le rôle **refuse de déployer** une destination `wasbs://` sans chaîne de
connexion. Le `.env` généré ne porte alors que
`AZURE_STORAGE_CONNECTION_STRING` ; les clients (`serving`, `training`) n'ont
besoin que de `MLFLOW_TRACKING_URI` — le serveur relaie tout.

La VM doit avoir un accès **HTTPS sortant** vers `*.blob.core.windows.net`.

## Pas de route Traefik

MLflow n'a **aucune authentification propre**, et déplacer un alias dans le
registre suffit à changer le modèle servi en production. Le port n'est publié
que sur la boucle locale ; l'interface se consulte par tunnel SSH :

```
ssh -L 5000:127.0.0.1:5000 <hote>   puis http://localhost:5000
```

## Qui se connecte

| Client | Usage |
|---|---|
| `training` | enregistre les runs et les versions (`MLFLOW_TRACKING_URI`) |
| `serving` | résout l'alias `champion` au démarrage |
| exploitant | interface, par tunnel SSH |

## Dépannage

| Symptôme | Piste |
|---|---|
| `serving` : 503 au démarrage | registre injoignable, ou alias `champion` absent |
| client : `Invalid Host header` / 403 | hôte absent de `--allowed-hosts` |
| dépôt d'artefact : `Fail to upload` | chaîne Azure absente/erronée, ou pas d'accès sortant vers `blob.core.windows.net` |
| build échoue sur `pip install` | pas d'accès réseau au moment du `provision.yml` |
