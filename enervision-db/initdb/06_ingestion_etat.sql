-- ============================================================
-- EV-18 — `ingestion_etat` : ce que la table `mesure` ne sait pas dire
--
-- Nouveau fichier de migration : le schéma figé v1.0 reste intact,
-- sa propre règle d'évolution l'impose (voir 01_schema.sql). Même
-- forme que 03 et 05, à appliquer à la main sur les bases déjà
-- démarrées, dont initdb n'est plus rejoué :
--
--   psql -U enervision -d enervision -f 06_ingestion_etat.sql
--
-- POURQUOI UNE TABLE, ET NON UN AGRÉGAT SUR `mesure`
-- --------------------------------------------------
-- La fraîcheur d'ingestion se lit presque partout dans
-- mesure.inserted_at : max(inserted_at) par site dit quand la
-- dernière ligne est entrée. Presque, parce que cet agrégat ne
-- répond que lorsqu'il y a des lignes.
--
-- Un capteur mort produit quand même une mesure — nulle, avec ses
-- null_reasons : la ligne entre, inserted_at avance, et l'agrégat
-- fonctionne. Mais un poller arrêté, une source qui répond 500, une
-- base injoignable ne produisent RIEN. max(inserted_at) se fige
-- alors exactement comme si le site avait cessé d'exister, et c'est
-- la panne la plus grave qui devient la plus discrète.
--
-- Aucune requête sur `mesure` ne peut distinguer « la collecte a
-- tourné et la source n'avait rien » de « la collecte n'a pas
-- tourné ». Seul le collecteur le sait, et jusqu'ici il ne le disait
-- qu'à son journal (collector/poller.py, _log_tick et _log_skew).
-- Cette table est l'endroit où il le dit à la base.
--
-- UNE LIGNE PAR SITE, ET NON UN JOURNAL PAR TICK
-- ----------------------------------------------
-- Sept sites interrogés à la minute produiraient environ dix mille
-- lignes par jour, qu'il faudrait purger. Or la question posée par
-- le dashboard est au présent : « ce site est-il encore collecté ».
-- Sept lignes en upsert y répondent exactement.
--
-- L'historique du retard n'est pas perdu pour autant : il est déjà
-- dans le journal du collecteur, et EV-30 le porte vers Prometheus,
-- dont c'est le métier. Une table de séries temporelles écrite à la
-- main serait un troisième endroit, moins bon que les deux autres.
--
-- CE QUE CHAQUE COLONNE PERMET DE DISTINGUER
-- ------------------------------------------
-- last_attempt_at et last_success_at sont séparés, et c'est tout
-- l'intérêt de la table. Égales, la collecte va bien. Écartées, le
-- collecteur tourne et échoue — l'écart dit depuis quand. Toutes
-- deux figées, c'est le collecteur lui-même qui ne tourne plus, ce
-- qu'une seule date n'aurait pas permis de voir.
--
-- last_data_lag_s est l'âge de la mesure servie par la source au
-- moment du tick, mesuré par le collecteur. Il n'est pas
-- reconstructible depuis inserted_at - ts : cette différence-là
-- mélange le retard de la source et celui de l'écriture, et un
-- rattrapage de journée la rend énorme sans qu'aucune panne
-- n'existe.
--
-- consecutive_failures distingue l'à-coup de la panne installée.
-- Remis à zéro par un succès, jamais décrémenté.
--
-- source dit lequel des deux points d'entrée a écrit la ligne. Un
-- rattrapage manuel (`python -m collector`) ne doit pas se faire
-- passer pour une collecte vivante (`python -m collector.poller`),
-- sinon la fraîcheur affichée devient un mensonge le jour où le
-- poller est arrêté et où quelqu'un rejoue une journée à la main.
--
-- IDEMPOTENT : rejouable sur une base déjà à jour.
-- ============================================================

CREATE TABLE IF NOT EXISTS ingestion_etat (
    site_id             VARCHAR(20)  PRIMARY KEY REFERENCES site(site_id),
    -- Dernière fois que le collecteur a essayé, qu'il ait réussi ou non.
    last_attempt_at     TIMESTAMPTZ  NOT NULL,
    -- Dernière fois qu'il a abouti. NULL tant qu'aucun essai n'a réussi :
    -- un site jamais collecté n'est pas un site collecté à l'epoch.
    last_success_at     TIMESTAMPTZ,
    -- Lignes soumises par le dernier essai réussi. Zéro est une réponse
    -- valable : la source a répondu, elle n'avait rien de nouveau.
    last_rows           INTEGER      NOT NULL DEFAULT 0,
    -- Âge de la mesure servie par la source, en secondes, au dernier essai
    -- réussi. NULL quand la source n'a rien servi.
    last_data_lag_s     NUMERIC(10,2),
    consecutive_failures INTEGER     NOT NULL DEFAULT 0
                         CHECK (consecutive_failures >= 0),
    -- Cause du dernier échec, telle que le collecteur l'a journalisée.
    -- Conservée après un succès : savoir de quoi on relève a une valeur.
    last_error          TEXT,
    source              VARCHAR(20)  NOT NULL
                        CHECK (source IN ('poller', 'backfill')),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE ingestion_etat IS
    'Etat courant de la collecte, une ligne par site. Ecrite par le'
    ' collecteur (poller et rattrapage), lue par l''API metier pour'
    ' l''indicateur de fraicheur d''ingestion. Repond a la question que'
    ' mesure.inserted_at ne peut pas trancher : la collecte a-t-elle'
    ' tourne, ou n''y avait-il rien a collecter.';

COMMENT ON COLUMN ingestion_etat.last_attempt_at IS
    'Dernier essai de collecte, abouti ou non. Compare a last_success_at :'
    ' egales, la collecte va bien ; ecartees, elle tourne et echoue ; les'
    ' deux figees, le collecteur lui-meme ne tourne plus.';

COMMENT ON COLUMN ingestion_etat.last_success_at IS
    'Dernier essai abouti. NULL tant qu''aucun n''a reussi.';

COMMENT ON COLUMN ingestion_etat.last_data_lag_s IS
    'Age de la mesure servie par la source au dernier essai reussi, en'
    ' secondes, mesure par le collecteur. Distinct de'
    ' inserted_at - ts, qui melange retard de source et retard d''ecriture'
    ' et devient enorme sur un rattrapage sans qu''aucune panne n''existe.';

COMMENT ON COLUMN ingestion_etat.consecutive_failures IS
    'Echecs consecutifs depuis le dernier succes. Remis a zero par un'
    ' succes, jamais decremente : il distingue l''a-coup de la panne'
    ' installee.';

COMMENT ON COLUMN ingestion_etat.source IS
    'Point d''entree ayant ecrit la ligne : poller pour la collecte'
    ' continue, backfill pour un rattrapage manuel. Un rattrapage ne doit'
    ' pas se faire passer pour une collecte vivante.';
