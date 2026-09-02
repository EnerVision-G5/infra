-- ============================================================
-- EV-12 — Comptes locaux et rôles reader / writer sur app_user
--
-- Nouveau fichier de migration : le schéma figé v1.0 reste intact,
-- sa propre règle d'évolution l'impose (voir 01_schema.sql).
--
-- POURQUOI CETTE MIGRATION
-- ------------------------
-- app_user modélisait une fédération d'identité externe
-- (oauth_provider 'keycloak' ou 'google', oauth_subject, et pas de
-- mot de passe : « l'identité vient du provider »). ADR-009 a
-- écarté cette option, retenu le flux OAuth2 mot de passe avec des
-- JWT signés par l'API, et acté en conséquence que « les mots de
-- passe sont stockés hachés ». Le contrat gelé décrit un formulaire
-- username + password sur POST /api/v1/auth/token et publie
-- UserOut.role sur les seules valeurs reader et writer.
-- La base s'aligne donc sur le contrat (daily du 02/09/2026).
--
-- MODÉLISATION RETENUE
-- --------------------
-- Un compte local est une ligne avec oauth_provider = 'local' et
-- oauth_subject = le username. Aucune colonne d'identité n'est
-- ajoutée : la contrainte UNIQUE (oauth_provider, oauth_subject)
-- déjà en place devient la clé de connexion, et oauth_subject porte
-- par construction le claim « sub » du JWT que l'API émet. Une
-- fédération réelle reste possible plus tard sous un autre
-- oauth_provider, sans nouvelle migration.
--
-- IDEMPOTENT : rejouable sur une base déjà à jour, y compris sur une
-- base de production dont les scripts d'initdb ne sont plus rejoués.
--
--   psql -U enervision -d enervision -f 04_app_user_auth.sql
-- ============================================================

-- 1. Colonne de hachage. Nullable à dessein : une ligne fédérée
-- future n'a pas de mot de passe local, et l'API refuse alors
-- l'authentification par mot de passe pour ce compte.
ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);

-- 2. L'ancienne contrainte part AVANT la conversion : elle
-- n'autorise pas les valeurs cibles, l'UPDATE de l'étape 3 la
-- violerait.
ALTER TABLE app_user
    DROP CONSTRAINT IF EXISTS app_user_role_check;

-- 3. Conversion des lignes existantes : admin et analyst avaient un
-- pouvoir d'écriture, viewer non.
UPDATE app_user
   SET role = CASE role
                  WHEN 'admin'   THEN 'writer'
                  WHEN 'analyst' THEN 'writer'
                  WHEN 'viewer'  THEN 'reader'
              END
 WHERE role IN ('admin', 'analyst', 'viewer');

-- 4. Le défaut suit les nouvelles valeurs, au moindre privilège.
ALTER TABLE app_user
    ALTER COLUMN role SET DEFAULT 'reader';

-- 5. Nouvelle contrainte, mêmes valeurs que l'énumération
-- UserOut.role du contrat gelé.
ALTER TABLE app_user
    ADD CONSTRAINT app_user_role_check
    CHECK (role IN ('reader', 'writer'));

-- Les commentaires de 01_schema.sql ne peuvent pas être corrigés
-- (fichier figé) : ils le sont ici, en base, pour que \d+ app_user
-- ne raconte pas l'inverse de ce que fait l'API.
COMMENT ON TABLE app_user IS
    'Utilisateurs de l''API. Un compte local porte oauth_provider = ''local'','
    ' oauth_subject = son username et password_hash renseigné (ADR-009).';

COMMENT ON COLUMN app_user.oauth_provider IS
    'Origine de l''identité. ''local'' pour un compte authentifié par mot de'
    ' passe contre cette table ; un nom de fournisseur pour une identité'
    ' fédérée, cas non implémenté à ce jour.';

COMMENT ON COLUMN app_user.oauth_subject IS
    'Identifiant de connexion, publié tel quel dans UserOut.username et dans'
    ' le claim sub du JWT. Unique par oauth_provider.';

COMMENT ON COLUMN app_user.password_hash IS
    'Hachage bcrypt du mot de passe, produit par l''API (passlib) ou par le'
    ' seed de développement (pgcrypto). Jamais de mot de passe en clair.'
    ' NULL pour une identité fédérée, qui ne peut alors pas se connecter par'
    ' mot de passe.';

COMMENT ON COLUMN app_user.role IS
    'Rôle applicatif, aligné sur UserOut.role du contrat gelé : reader en'
    ' lecture seule, writer en écriture.';
