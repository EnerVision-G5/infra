#!/usr/bin/env bash
#
# Fabrique un jeton de notre émetteur, pour tester ou dépanner une identité
# applicative sans passer par une API : le même JWT que celui que le code
# Python produit (docs/identites-applicatives.md).
#
#   bash terraform/scripts/workload-token.sh <clé privée .pem> <issuer> <sujet>
#
#   iss = sortie Terraform workload_issuer, sub = <env>/<nom> (sortie
#   workload_identities), aud fixe : api://AzureADTokenExchange. Valable
#   cinq minutes. Pour l'échanger contre une session Azure :
#
#   az login --service-principal -t <tenant> -u <client_id> --federated-token "$(bash … )"
#   az storage blob list --auth-mode login --account-name <compte> -c dev-data -o table
#
# openssl et python3 (bibliothèque standard) seulement.

set -euo pipefail

key_file="${1:?usage : workload-token.sh <clé privée> <issuer> <sujet>}"
issuer="${2:?usage : workload-token.sh <clé privée> <issuer> <sujet>}"
subject="${3:?usage : workload-token.sh <clé privée> <issuer> <sujet>}"
# kid : celui écrit par issuer-keygen.sh à côté de la clé, sinon KID.
kid_file="${key_file%.pem}.kid"
kid="${KID:-$( [ -f "$kid_file" ] && cat "$kid_file" || echo "")}"
[ -n "$kid" ] || { echo "kid inconnu : fichier $kid_file absent, ou KID=… dans l'environnement" >&2; exit 1; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now="$(date +%s)"
header="$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$kid" | b64url)"
payload="$(printf '{"iss":"%s","sub":"%s","aud":"api://AzureADTokenExchange","iat":%s,"nbf":%s,"exp":%s,"jti":"%s"}' \
  "$issuer" "$subject" "$now" "$now" "$((now + 300))" "$(python3 -c 'import uuid;print(uuid.uuid4())')" | b64url)"
signature="$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key_file" -binary | b64url)"

printf '%s.%s.%s\n' "$header" "$payload" "$signature"
