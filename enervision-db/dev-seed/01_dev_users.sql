-- ============================================================
-- EV-12 — Utilisateurs de DÉVELOPPEMENT
--
--                  NE PAS APPLIQUER EN PRODUCTION
--
-- Ce fichier est délibérément HORS de initdb/. Les scripts d'initdb
-- s'exécutent au premier démarrage de n'importe quelle base, celle
-- de production comprise : deux comptes dont le mot de passe est
-- connu de tout le dépôt n'ont rien à y faire. Un garde par
-- variable d'environnement aurait suffi tant que personne ne se
-- trompe de configuration ; le placer hors du dossier automatique
-- rend l'accident impossible plutôt qu'improbable.
--
-- L'appliquer demande donc un geste explicite :
--
--   DEV_USERS_PASSWORD='...' psql -U enervision -d enervision \
--       -f enervision-db/dev-seed/01_dev_users.sql
--
--   # ou, sur la pile de développement conteneurisée :
--   docker compose exec -e DEV_USERS_PASSWORD='...' timescaledb \
--       psql -U enervision -d enervision \
--       -f /dev-seed/01_dev_users.sql
--
-- Aucun mot de passe n'est écrit ici : il est lu dans
-- DEV_USERS_PASSWORD et haché par pgcrypto au moment du seed, en
-- bcrypt, le même algorithme que celui dont l'API se sert pour
-- vérifier. Faute de variable, le défaut est « changeme-dev », qui
-- annonce ce qu'il vaut.
--
-- Prérequis : 04_app_user_auth.sql appliqué (colonne password_hash
-- et rôles reader / writer).
--
-- IDEMPOTENT : rejouable, l'UPSERT réécrit les deux comptes. C'est
-- aussi le moyen de changer leur mot de passe.
-- ============================================================

\getenv dev_users_password DEV_USERS_PASSWORD
\if :{?dev_users_password}
\else
\set dev_users_password 'changeme-dev'
\endif

-- gen_salt et crypt viennent de pgcrypto. L'extension n'est créée
-- que par ce script de développement : la production n'en a pas
-- besoin, c'est l'API qui y hache les mots de passe.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Coût 12, comme le défaut de passlib côté API : un hachage produit
-- ici et un hachage produit par l'API sont interchangeables.
INSERT INTO app_user (
    oauth_provider,
    oauth_subject,
    email,
    display_name,
    role,
    password_hash
) VALUES
    ('local', 'dev.reader', 'dev.reader@enervision.local',
     'Dev Reader (dev-only)', 'reader',
     crypt(:'dev_users_password', gen_salt('bf', 12))),
    ('local', 'dev.writer', 'dev.writer@enervision.local',
     'Dev Writer (dev-only)', 'writer',
     crypt(:'dev_users_password', gen_salt('bf', 12)))
ON CONFLICT (oauth_provider, oauth_subject) DO UPDATE SET
    email         = EXCLUDED.email,
    display_name  = EXCLUDED.display_name,
    role          = EXCLUDED.role,
    password_hash = EXCLUDED.password_hash;

-- Rappel à l'écran, pour qu'un seed lancé par distraction sur la
-- mauvaise base ne passe pas inaperçu.
\echo '>>> Comptes de DEVELOPPEMENT dev.reader et dev.writer crees ou mis a jour.'
\echo '>>> Ne jamais appliquer ce script sur une base de production.'
