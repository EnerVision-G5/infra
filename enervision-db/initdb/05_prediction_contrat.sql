-- ============================================================
-- EV-38 — Les trois champs du contrat que `prediction` ne porte pas
--
-- Nouveau fichier de migration : le schéma figé v1.0 reste intact,
-- sa propre règle d'évolution l'impose (voir 01_schema.sql). Même
-- forme que 03_mesure_imputation.sql, à appliquer à la main sur les
-- bases déjà démarrées, dont initdb n'est plus rejoué.
--
--   psql -U enervision -d enervision -f 05_prediction_contrat.sql
--
-- Numérotée 05 et non 04 : 04_app_user_auth.sql est déjà pris.
--
-- POURQUOI CES TROIS COLONNES, ET PAS QUATRE
-- ------------------------------------------
-- Le contrat publie six champs par point de prévision. Trois sont
-- déjà là, sous un autre nom ou par normalisation :
--
--   timestamp                -> prediction.ts_cible
--   predicted_consumption_kw -> prediction.consumption_kw_predite
--   model_version            -> modele.version, par le join sur
--                               prediction.modele_id
--
-- model_version n'est donc PAS ajouté ici. C'est exactement la même
-- valeur : le service d'inférence la lit dans le registre MLflow
-- (_version_of rend str(entry.version)) et l'entraînement repose
-- cette même version dans `modele` à la promotion. Une colonne de
-- plus dupliquerait un fait déjà porté, avec le risque ordinaire des
-- doublons : deux valeurs qui divergent et plus personne pour dire
-- laquelle fait foi.
--
-- modele_id reste NOT NULL. C'est ce qui garantit que le join
-- aboutit, et la table `modele` est alimentée à chaque promotion.
--
-- Un seul cas rend le join muet : un modèle chargé par chemin
-- d'artefact au lieu d'un alias n'a pas d'entrée de registre, et
-- _version_of retombe alors sur l'identifiant interne, qui ne
-- correspond à aucune ligne de `modele`. C'est un déploiement
-- dégradé, pas le cas nominal.
--
-- LES TROIS QUI MANQUENT VRAIMENT
-- -------------------------------
-- generated_at n'existe sous aucun nom. Les quatre TIMESTAMPTZ du
-- schéma datent tous autre chose : prediction.created_at l'insertion,
-- prediction.ts_cible l'heure prévue, modele.date_entrainement le run
-- d'entraînement, mesure.inserted_at le chargement d'une mesure.
-- created_at est le faux ami de la série : l'écart avec l'heure réelle
-- de production est de quelques millisecondes quand l'archivage suit
-- la prévision, et se creuse dès qu'il est rejoué, mis en lot ou
-- repris après incident. À ce moment-là, plus rien ne permet de
-- retrouver l'heure de production.
--
-- lower_bound_kw et upper_bound_kw n'existent pas et ne sont pas
-- reconstructibles depuis la base, contrairement à model_version. La
-- bande vaut valeur ± 1.96 × residual_std × racine(step), et deux des
-- trois entrées manquent : residual_std est un tag de version MLflow,
-- sans colonne dans `modele`, et step est le rang dans la récurrence
-- depuis la dernière mesure observée, origine que rien ne conserve.
-- Les deux manques se tiennent : même en ajoutant residual_std, sans
-- generated_at les bandes resteraient irrécupérables.
--
-- Nullables, et non NOT NULL : le service rend null quand le tag
-- residual_std manque, et forcer une valeur ferait passer « pas
-- d'intervalle » pour « intervalle de largeur nulle », c'est-à-dire
-- une prévision annoncée comme certaine. NUMERIC(10,2) pour
-- s'aligner sur consumption_kw_predite.
--
-- IDEMPOTENT : rejouable sur une base déjà à jour.
-- ============================================================

ALTER TABLE prediction
    ADD COLUMN IF NOT EXISTS lower_bound_kw NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS upper_bound_kw NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS generated_at   TIMESTAMPTZ;

COMMENT ON COLUMN prediction.generated_at IS
    'Horodatage de production de la prevision par le service d''inference,'
    ' distinct de created_at qui date l''insertion. Publie dans'
    ' PredictionPointOut.generated_at.';

COMMENT ON COLUMN prediction.lower_bound_kw IS
    'Borne basse de l''intervalle de confiance. NULL quand la version servie'
    ' ne declare pas sa dispersion : pas d''intervalle, et non un intervalle'
    ' de largeur nulle.';

COMMENT ON COLUMN prediction.upper_bound_kw IS
    'Borne haute de l''intervalle de confiance. NULL dans le meme cas que'
    ' lower_bound_kw.';
