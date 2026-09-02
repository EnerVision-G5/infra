#!/usr/bin/env python3
"""Génère le SQL de seed des utilisateurs de DÉVELOPPEMENT.

                  NE PAS APPLIQUER EN PRODUCTION

Ce script écrit du SQL sur la sortie standard, il ne touche pas la base
lui-même : le SQL est relisible avant d'être appliqué, et aucun pilote de base
n'est nécessaire pour l'exécuter.

    DEV_USERS_PASSWORD='...' python enervision-db/dev-seed/dev_users.py \\
        | psql -U enervision -d enervision

    # ou, sur la pile de développement conteneurisée :
    DEV_USERS_PASSWORD='...' python enervision-db/dev-seed/dev_users.py \\
        | docker compose exec -T timescaledb psql -U enervision -d enervision

Prérequis : pip install -r enervision-db/dev-seed/requirements.txt

POURQUOI UN SCRIPT PYTHON PLUTÔT QU'UN FICHIER .SQL
---------------------------------------------------
Les mots de passe sont hachés en argon2id, et PostgreSQL ne sait pas le faire :
son extension pgcrypto ne propose que bcrypt, md5, des et xdes. Produire les
hachages avec une autre bibliothèque que celle de l'API reviendrait à faire
reposer la connexion sur la compatibilité de deux implémentations distinctes.
Ce script utilise donc exactement la même, argon2-cffi, avec les mêmes
paramètres par défaut qu'app/password.py côté API.

CE FICHIER EST HORS DE initdb/ À DESSEIN
----------------------------------------
Les scripts d'initdb s'exécutent au premier démarrage de n'importe quelle base,
celle de production comprise, et deux comptes dont le mot de passe est connu du
dépôt n'y ont pas leur place. L'appliquer demande un geste explicite.

Aucun mot de passe n'est écrit ici : il est lu dans DEV_USERS_PASSWORD et haché
au moment de la génération. Faute de variable, le défaut est « changeme-dev »,
qui annonce ce qu'il vaut.

Prérequis en base : 04_app_user_auth.sql appliqué (colonne password_hash et
rôles reader / writer).

IDEMPOTENT : le SQL produit est un UPSERT, rejouable. C'est aussi le moyen de
changer le mot de passe des deux comptes.
"""

from __future__ import annotations

import os
import sys

from argon2 import PasswordHasher

DEFAULT_PASSWORD = "changeme-dev"

# Paramètres par défaut d'argon2-cffi, ceux d'app/password.py côté API : un
# hachage produit ici et un hachage produit par l'API sont interchangeables.
HASHER = PasswordHasher()

# (username, email, display_name, role)
DEV_USERS = (
    ("dev.reader", "dev.reader@enervision.local", "Dev Reader (dev-only)", "reader"),
    ("dev.writer", "dev.writer@enervision.local", "Dev Writer (dev-only)", "writer"),
)

HEADER = """-- SQL genere par enervision-db/dev-seed/dev_users.py
-- COMPTES DE DEVELOPPEMENT : ne jamais appliquer en production.
-- Les hachages ci-dessous sont en argon2id, produits par argon2-cffi.

BEGIN;
"""

FOOTER = """
COMMIT;
"""


def quote(value: str) -> str:
    """Met une valeur entre apostrophes en doublant celles qu'elle contient.

    Les hachages argon2id ne contiennent ni apostrophe ni antislash, et les
    identifiants ci-dessus sont écrits en dur : l'échappement est là par
    principe, pour qu'ajouter un compte à la liste ne devienne pas une
    injection SQL.
    """
    return "'" + value.replace("'", "''") + "'"


def build_sql(password: str) -> str:
    """Retourne l'UPSERT des comptes de développement."""
    rows = []
    for username, email, display_name, role in DEV_USERS:
        columns = (
            "'local'",
            quote(username),
            quote(email),
            quote(display_name),
            quote(role),
            quote(HASHER.hash(password)),
        )
        rows.append("    (" + ", ".join(columns) + ")")

    return (
        HEADER
        + "\nINSERT INTO app_user (\n"
        "    oauth_provider,\n"
        "    oauth_subject,\n"
        "    email,\n"
        "    display_name,\n"
        "    role,\n"
        "    password_hash\n"
        ") VALUES\n" + ",\n".join(rows) + "\n"
        "ON CONFLICT (oauth_provider, oauth_subject) DO UPDATE SET\n"
        "    email         = EXCLUDED.email,\n"
        "    display_name  = EXCLUDED.display_name,\n"
        "    role          = EXCLUDED.role,\n"
        "    password_hash = EXCLUDED.password_hash;\n" + FOOTER
    )


def main() -> int:
    password = os.environ.get("DEV_USERS_PASSWORD") or DEFAULT_PASSWORD
    if password == DEFAULT_PASSWORD:
        # Sur stderr : le SQL de stdout part dans psql, cet avertissement doit
        # rester visible dans le terminal.
        print(
            "Attention : DEV_USERS_PASSWORD n'est pas defini,"
            f" le mot de passe des comptes de dev sera « {DEFAULT_PASSWORD} ».",
            file=sys.stderr,
        )
    sys.stdout.write(build_sql(password))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
