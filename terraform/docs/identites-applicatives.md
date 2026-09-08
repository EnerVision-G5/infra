# Identités applicatives : une API on-premise accède aux blobs

Comment une API Python sur la VM de l'école lit ou écrit dans le conteneur
d'un environnement, **sans clé de compte ni secret côté Azure**.

## Le mécanisme

Azure ne peut pas donner d'identité managée à une machine hors Azure, et
le locataire de l'école interdit les principaux de service classiques.
Reste la fédération d'identité, celle que la CI utilise déjà avec GitHub :

1. Une **identité managée** par niveau de droit existe dans le groupe
   (`id-enervision-dev-api-rw`, `id-enervision-dev-api-ro`), avec ses rôles
   sur les conteneurs de l'environnement, posés par Terraform.
2. Chacune porte un **identifiant fédéré** qui fait confiance à **notre
   émetteur** : une paire de clés par environnement. La clé privée reste
   on-premise ; la clé publique est publiée par Terraform sur le site
   statique du compte du projet, avec le document de découverte OpenID :
   `https://<compte>.z28.web.core.windows.net/dev/.well-known/openid-configuration`.
3. L'API signe un petit jeton (JWT, RS256) avec la clé privée : `iss` =
   l'émetteur, `sub` = `dev/api-rw`, `aud` = `api://AzureADTokenExchange`,
   cinq minutes de validité. Elle le présente à Entra ID, qui vérifie la
   signature contre le JWKS publié et rend un jeton d'accès au nom de
   l'identité. Le SDK fait cet échange et le renouvellement tout seul.

Ce qu'un attaquant devrait voler : la clé privée, sur la VM. Un jeton
intercepté vaut cinq minutes et n'est bon que pour cette identité.

## Les deux clés : qui fait quoi, où va quoi

Une paire de clés par environnement, générée par `issuer-keygen.sh`. Les
deux moitiés ne servent pas à la même chose et ne vont pas au même endroit.

| | Clé privée | Clé publique (JWK : `kid`, `n`, `e`) |
| --- | --- | --- |
| À quoi elle sert | **Signer** les jetons : prouver que c'est bien nous | **Vérifier** les signatures : Azure s'en sert pour contrôler chaque jeton reçu |
| Qui l'utilise | l'API Python, au moment de demander un accès (`workload-token.sh` pour tester) | Entra ID, à chaque échange de jeton |
| Où elle vit | vault Ansible → montée dans le conteneur de l'API (`WORKLOAD_KEY_FILE`) ; copie de travail dans `~/.enervision/` de celui qui l'a générée | `<ENV>.auto.tfvars` (`workload_issuer_jwks`), donc dans Git ; publiée par Terraform dans le JWKS du site statique |
| Secret ? | **Oui.** Jamais dans Git, jamais dans Terraform ni dans l'état, jamais dans un `.env` versionné | **Non.** Versionnable, lisible par tous : elle ne permet que de vérifier, pas de signer |
| Si elle fuit | rotation immédiate (section plus bas) : quiconque la détient peut se faire passer pour l'API | rien à faire |

Et qui fait quoi, dans l'ordre :

| Acteur | Fait | Avec |
| --- | --- | --- |
| `issuer-keygen.sh` (une personne, une fois par environnement) | crée la paire, écrit la clé privée hors du dépôt, affiche la clé publique | openssl |
| Terraform (PR puis apply) | publie découverte + JWKS sur le site statique, crée les identités `api-rw` / `api-ro`, leur identifiant fédéré (émetteur + sujet attendus), leurs rôles sur le conteneur | la clé publique du tfvars |
| Ansible | dépose la clé privée et le `.env` sur la VM, comme les autres secrets | le vault |
| L'API | signe un jeton (`iss`, `sub`, `aud`, cinq minutes), l'échange contre un jeton Azure, lit ou écrit les blobs | la clé privée, `client_id`, `WORKLOAD_SUBJECT` |
| Entra ID | lit le JWKS à l'URL de l'émetteur, vérifie la signature, l'émetteur et le sujet, rend un jeton au nom de l'identité | la clé publique publiée |

Rien à retenir de plus que ça : **la privée signe et reste chez nous, la
publique vérifie et se publie.**

## Mettre en place un environnement (une fois)

```bash
# 1. La paire de clés, sur le poste de celui qui tient l'environnement
bash terraform/scripts/issuer-keygen.sh DEV
```

Le script écrit la clé privée hors du dépôt (`~/.enervision/issuer-dev.pem`,
et son `kid` à côté) et affiche le bloc `workload_issuer_jwks` à coller dans
`terraform/DEV/DEV.auto.tfvars`. Ce bloc est la clé publique : versionnable.

```bash
# 2. PR, relecture du plan (identités, identifiants fédérés, deux blobs, rôles), fusion, lancement manuel de l'apply
# 3. Les valeurs pour les API
cd terraform/DEV && terraform output workload_identities
```

La clé privée va dans le vault Ansible ; les valeurs de l'API dans son
`.env`, déployé par le rôle `applications` comme les autres.

## Côté API

Huit variables. Seules deux changent d'une API à l'autre, et elles vont
ensemble : l'identité demandée et le sujet du jeton.

| Variable | API qui écrit | API qui ne fait que lire | Source |
| --- | --- | --- | --- |
| `AZURE_CLIENT_ID` | `client_id` de **`api-rw`** | `client_id` de **`api-ro`** | `terraform output workload_identities` |
| `WORKLOAD_SUBJECT` | **`dev/api-rw`** | **`dev/api-ro`** | idem |
| `AZURE_TENANT_ID` | le locataire | idem | `az account show --query tenantId` |
| `WORKLOAD_ISSUER` | `https://<compte>.z28.web.core.windows.net/dev` | idem | `terraform output workload_issuer` |
| `WORKLOAD_KEY_FILE` | chemin de la clé privée montée dans le conteneur | idem, **la même clé** | vault Ansible |
| `WORKLOAD_KID` | `dev-20260908` | idem | fichier `.kid` à côté de la clé |
| `BLOB_ACCOUNT_URL` | `https://<compte>.blob.core.windows.net` | idem | `terraform output blob_endpoint` |
| `BLOB_CONTAINER` | `dev-data` | idem | `terraform output storage_containers` |

Le rôle Ansible `applications` produit ce `.env` comme celui de l'API
métier : les valeurs communes dans `vars.yml`, la clé dans le vault.

Dépendances : `azure-identity`, `azure-storage-blob`, `PyJWT[crypto]`.

```python
import os, time, uuid
import jwt
from azure.identity import ClientAssertionCredential
from azure.storage.blob import ContainerClient


def workload_assertion() -> str:
    """Jeton signé par notre émetteur ; le SDK l'appelle à chaque renouvellement."""
    now = int(time.time())
    with open(os.environ["WORKLOAD_KEY_FILE"], "rb") as f:
        key = f.read()
    return jwt.encode(
        {
            "iss": os.environ["WORKLOAD_ISSUER"],
            "sub": os.environ["WORKLOAD_SUBJECT"],
            "aud": "api://AzureADTokenExchange",
            "iat": now, "nbf": now, "exp": now + 300,
            "jti": str(uuid.uuid4()),
        },
        key,
        algorithm="RS256",
        headers={"kid": os.environ["WORKLOAD_KID"]},
    )


credential = ClientAssertionCredential(
    tenant_id=os.environ["AZURE_TENANT_ID"],
    client_id=os.environ["AZURE_CLIENT_ID"],
    func=workload_assertion,
)
container = ContainerClient(os.environ["BLOB_ACCOUNT_URL"], os.environ["BLOB_CONTAINER"], credential)

container.upload_blob("rapports/2026-09-08.csv", data, overwrite=True)   # api-rw
blob = container.download_blob("rapports/2026-09-08.csv").readall()      # api-rw ou api-ro
```

Une API de niveau `ro` qui tente d'écrire reçoit `AuthorizationPermissionMismatch`
: c'est le rôle `Storage Blob Data Reader` qui parle, pas un bug.

## D'où viennent les droits

Le jeton ne contient ni « lecture » ni « écriture ». Il ne dit qu'une
chose : *qui* parle (`sub` = `dev/api-rw` ou `dev/api-ro`). Entra ID
l'échange contre un jeton **au nom de l'identité managée** correspondante,
et c'est le stockage qui applique les rôles posés sur cette identité par
Terraform (`iam.tf`) : `api-rw` a *Storage Blob Data Contributor* sur le
conteneur, `api-ro` a *Storage Blob Data Reader*. Même code, même clé
privée, même émetteur : seule l'identité qu'on prétend être change, et
avec elle ce qu'Azure accepte. Retirer un droit se fait dans Terraform,
sans toucher à l'API ni à la clé.

## Trois durées, rien à renouveler à la main

| Objet | Vit | Renouvelé par |
| --- | --- | --- |
| La clé privée | des mois, jusqu'à une rotation décidée | vous, rarement (section Rotation) |
| Le jeton que l'API signe avec la clé | **5 minutes** | l'API, sans réseau, en une milliseconde, chaque fois que le SDK le demande |
| Le jeton d'accès rendu par Entra ID | environ 1 heure | le SDK, en cache, ré-échangé à l'expiration |

Les cinq minutes ne bloquent donc rien : ce jeton est jetable par
conception, et c'est une protection, un jeton intercepté ne vaut que cinq
minutes. Dans le code, c'est la fonction `workload_assertion` que le SDK
rappelle lui-même. Ce qui bloquerait une API : une clé privée absente, ou
qui ne correspond plus à la clé publique publiée (rotation mal faite).

## Démonstration

Un script fait tout le chemin, commenté étape par étape, et montre ce que
chaque identité peut faire :

```bash
python3 -m venv .venv && .venv/bin/pip install azure-identity azure-storage-blob "PyJWT[crypto]"
.venv/bin/python terraform/scripts/blob-demo.py DEV api-rw   # liste, écrit, lit
.venv/bin/python terraform/scripts/blob-demo.py DEV api-ro   # liste, écriture REFUSÉE, lit
```

Il lit les valeurs dans les sorties Terraform de l'environnement et la clé
privée dans `~/.enervision/`. Une vraie API fait exactement la même chose
avec son `.env` : le code de la section « Côté API » est celui du script.

## Tester sans API

```bash
issuer=$(cd terraform/DEV && terraform output -raw workload_issuer)
client=$(cd terraform/DEV && terraform output -json workload_identities | python3 -c 'import json,sys;print(json.load(sys.stdin)["api-rw"]["client_id"])')
token=$(bash terraform/scripts/workload-token.sh ~/.enervision/issuer-dev.pem "$issuer" dev/api-rw)
az login --service-principal -t <tenant> -u "$client" --federated-token "$token" --allow-no-subscriptions
az storage blob upload --auth-mode login --account-name <compte> -c dev-data -f README.md -n test.md
az logout   # puis az login pour retrouver votre session
```

`AADSTS700213` (« no matching federated identity record ») : le `sub` ou
l'`iss` présenté ne correspond pas à l'identifiant fédéré. `AADSTS700211`
ou une erreur de signature : le `kid` ou la clé ne sont pas ceux du JWKS
publié, ou Azure a encore l'ancien JWKS en cache (jusqu'à une heure).

## Rotation de la clé

Générer une nouvelle paire (`issuer-keygen.sh`, après avoir déplacé
l'ancienne), publier **les deux** clés publiques dans le JWKS le temps que
les API basculent, déployer la nouvelle clé privée par Ansible, puis
retirer l'ancienne du JWKS. Le module publie une clé ; pour la période de
recouvrement, ajouter temporairement la seconde dans `workload_identity.tf`
(`keys`) ou accepter une coupure de quelques minutes en environnement de
développement.

## Limites

- Le site statique sert les documents de l'émetteur en clair : c'est
  voulu, ce sont des clés publiques, et Azure doit pouvoir les lire.
- Une seule clé publiée à la fois par le module : la rotation sans coupure
  demande l'ajout manuel décrit ci-dessus.
- Le cache d'Entra ID sur le JWKS peut retarder une rotation d'une heure.
