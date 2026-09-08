#!/usr/bin/env bash
#
# Paire de clés de l'émetteur d'un environnement — celui qui signe les jetons
# que les API on-premise présentent à Azure (voir docs/identites-applicatives.md).
#
#   bash terraform/scripts/issuer-keygen.sh DEV
#
# Produit :
#   - la clé PRIVÉE, dans un fichier hors du dépôt (chemin affiché) : à mettre
#     dans le vault Ansible, jamais dans Git, jamais dans Terraform ;
#   - la clé PUBLIQUE au format JWK, à coller telle quelle dans
#     <ENV>.auto.tfvars (workload_issuer_jwks). Ce n'est pas un secret.
#
# Le kid porte la date : à la rotation, on génère une nouvelle paire, on
# publie les deux clés le temps que les API basculent, puis on retire
# l'ancienne. N'a besoin que d'openssl et de python3 (bibliothèque standard).

set -euo pipefail

env_name="${1:?usage : issuer-keygen.sh <ENV>   ex. issuer-keygen.sh DEV}"
env_lower="$(printf '%s' "$env_name" | tr '[:upper:]' '[:lower:]')"
kid="${env_lower}-$(date +%Y%m%d)"
out_dir="${ISSUER_KEY_DIR:-$HOME/.enervision}"
key_file="$out_dir/issuer-${env_lower}.pem"

mkdir -p "$out_dir"
chmod 700 "$out_dir"
if [ -e "$key_file" ]; then
  echo "Existe déjà : $key_file — le déplacer d'abord si vous voulez une nouvelle clé (rotation)." >&2
  exit 1
fi

umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$key_file" 2>/dev/null
# Le kid à côté de la clé : workload-token.sh et l'API doivent présenter
# exactement celui publié dans le JWKS.
printf '%s\n' "$kid" > "${key_file%.pem}.kid"

modulus_hex="$(openssl rsa -in "$key_file" -noout -modulus | cut -d= -f2)"
exponent_dec="$(openssl rsa -in "$key_file" -noout -text 2>/dev/null | sed -nE 's/^publicExponent: ([0-9]+).*/\1/p')"

jwk="$(MODULUS="$modulus_hex" EXPONENT="$exponent_dec" KID="$kid" python3 - <<'PY'
import base64, os
def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
n = bytes.fromhex(os.environ["MODULUS"])
e = int(os.environ["EXPONENT"]); e = e.to_bytes((e.bit_length() + 7) // 8, "big")
print(f'workload_issuer_jwks = {{\n  kid = "{os.environ["KID"]}"\n  n   = "{b64url(n)}"\n  e   = "{b64url(e)}"\n}}')
PY
)"

echo "Clé privée (vault Ansible, jamais dans Git) : $key_file   (kid : $kid, dans ${key_file%.pem}.kid)"
echo
echo "À coller dans terraform/${env_name}/${env_name}.auto.tfvars à la place de « workload_issuer_jwks = null » :"
echo
echo "$jwk"
