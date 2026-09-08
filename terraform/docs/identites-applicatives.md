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

Variables d'environnement, une identité par niveau de droit :

| Variable | Valeur | Source |
| --- | --- | --- |
| `AZURE_TENANT_ID` | locataire | secret GitHub du même nom, ou `az account show` |
| `AZURE_CLIENT_ID` | `client_id` de l'identité (`api-rw` ou `api-ro`) | `terraform output workload_identities` |
| `WORKLOAD_ISSUER` | URL de l'émetteur | `terraform output workload_issuer` |
| `WORKLOAD_SUBJECT` | `dev/api-rw` ou `dev/api-ro` | idem |
| `WORKLOAD_KEY_FILE` | chemin de la clé privée montée dans le conteneur | vault Ansible |
| `WORKLOAD_KID` | `kid` publié dans le JWKS | fichier `.kid` à côté de la clé |
| `BLOB_ACCOUNT_URL` | `https://<compte>.blob.core.windows.net` | `terraform output blob_endpoint` |
| `BLOB_CONTAINER` | `dev-data` | `terraform output storage_containers` |

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
