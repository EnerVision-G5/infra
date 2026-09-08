#!/usr/bin/env python3
"""Démonstration : une « API » on-premise accède aux blobs d'un environnement
sans aucun secret Azure, en se présentant comme l'une des identités
applicatives (api-rw ou api-ro).

    python3 terraform/scripts/blob-demo.py DEV api-rw
    python3 terraform/scripts/blob-demo.py DEV api-ro

Ce que le script montre, dans l'ordre :

  1. il signe un jeton avec la clé PRIVÉE de l'émetteur de l'environnement
     (~/.enervision/issuer-<env>.pem, produite par issuer-keygen.sh). Le jeton
     ne dit qu'une chose : « je suis <env>/<identité> » ;
  2. Entra ID vérifie la signature avec la clé PUBLIQUE publiée par Terraform,
     et rend un jeton d'accès AU NOM de l'identité managée correspondante ;
  3. il tente lister / écrire / lire dans le conteneur de l'environnement.
     Ce n'est pas le jeton qui dit « lecture » ou « écriture » : ce sont les
     rôles que Terraform a posés sur l'identité (iam.tf). api-ro se voit
     refuser l'écriture par le stockage, avec le même code et la même clé.

Les valeurs (émetteur, client_id, sujet, compte, conteneur) sont lues dans
les sorties Terraform de l'environnement ; une vraie API les recevrait par
son .env (docs/identites-applicatives.md). Dépendances :
    pip install azure-identity azure-storage-blob "PyJWT[crypto]"
"""

import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import jwt
from azure.core.exceptions import HttpResponseError
from azure.identity import ClientAssertionCredential
from azure.storage.blob import ContainerClient

AUDIENCE = "api://AzureADTokenExchange"
ROOT = Path(__file__).resolve().parent.parent


def die(message: str) -> None:
    print(f"KO   {message}", file=sys.stderr)
    sys.exit(1)


def terraform_outputs(env: str) -> dict:
    """Les sorties de l'environnement, comme `terraform output -json`."""
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / env}", "output", "-json"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        die(f"terraform output a échoué pour {env} : {result.stderr.strip()}")
    return {k: v["value"] for k, v in json.loads(result.stdout).items()}


def tenant_id() -> str:
    result = subprocess.run(["az", "account", "show", "--query", "tenantId", "-o", "tsv"],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        die("az account show a échoué : faire `az login` d'abord")
    return result.stdout.strip()


def main() -> None:
    if len(sys.argv) != 3:
        die("usage : blob-demo.py <ENV> <identité>   ex. blob-demo.py DEV api-rw")
    env, identity = sys.argv[1].upper(), sys.argv[2]
    env_lower = env.lower()

    key_file = Path(os.environ.get("WORKLOAD_KEY_FILE", Path.home() / ".enervision" / f"issuer-{env_lower}.pem"))
    kid_file = key_file.with_suffix(".kid")
    if not key_file.exists() or not kid_file.exists():
        die(f"clé privée ou kid absents : {key_file} / {kid_file} (issuer-keygen.sh {env})")
    private_key = key_file.read_bytes()
    kid = kid_file.read_text().strip()

    out = terraform_outputs(env)
    identities = out.get("workload_identities") or {}
    if identity not in identities:
        die(f"identité inconnue pour {env} : {identity} (connues : {', '.join(identities) or 'aucune, apply à faire'})")
    issuer, client_id, subject, level = out["workload_issuer"], identities[identity]["client_id"], identities[identity]["subject"], identities[identity]["level"]
    account_url, container = out["blob_endpoint"], out["storage_containers"][0]

    print(f"Identité   : {identity} (niveau {level}) — client_id {client_id}")
    print(f"Émetteur   : {issuer}")
    print(f"Sujet      : {subject}")
    print(f"Conteneur  : {account_url}{container}")
    print()

    # 1. Le jeton signé par notre clé privée. Il ne contient AUCUN droit :
    #    juste iss (qui signe), sub (qui je prétends être), aud (pour qui).
    def assertion() -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": issuer, "sub": subject, "aud": AUDIENCE, "iat": now, "nbf": now, "exp": now + 300, "jti": str(uuid.uuid4())},
            private_key, algorithm="RS256", headers={"kid": kid},
        )

    token = assertion()
    claims = jwt.decode(token, options={"verify_signature": False})
    print(f"1. Jeton signé (RS256, kid {kid}) : {json.dumps({k: claims[k] for k in ('iss', 'sub', 'aud')})}")

    # 2. L'échange : Entra ID vérifie la signature avec la clé publique du
    #    JWKS, puis rend un jeton d'accès au nom de l'identité managée.
    credential = ClientAssertionCredential(tenant_id(), client_id, assertion)
    try:
        access = credential.get_token("https://storage.azure.com/.default")
    except Exception as exc:  # noqa: BLE001 — on veut le message d'Entra ID
        die(f"échange refusé par Entra ID : {exc}")
    print(f"2. Jeton Azure obtenu au nom de {identity}, valable jusqu'à "
          f"{datetime.fromtimestamp(access.expires_on, tz=timezone.utc):%H:%M UTC}")
    print()

    # 3. Ce que cette identité peut faire : décidé par ses rôles, pas par le jeton.
    client = ContainerClient(account_url, container, credential)
    blob_name = f"demo/{identity}-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}.txt"

    def attempt(label: str, action) -> None:
        try:
            result = action()
            print(f"OK   {label}" + (f" → {result}" if result else ""))
        except HttpResponseError as exc:
            print(f"--   {label} → refusé par le stockage ({exc.error_code})")

    attempt("lister le conteneur", lambda: f"{sum(1 for _ in client.list_blobs())} blob(s)")
    attempt(f"écrire {blob_name}", lambda: client.upload_blob(blob_name, f"bonjour de {identity}\n".encode()) and "écrit")
    existing = next(iter(client.list_blobs()), None)
    if existing:
        attempt(f"lire {existing.name}", lambda: f"{len(client.download_blob(existing.name).readall())} octets")
    else:
        print("--   rien à lire : le conteneur est vide (lancer d'abord avec api-rw)")


if __name__ == "__main__":
    main()
