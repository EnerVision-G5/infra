-- ============================================================
-- EV-18 — `mesure.quality_source` : qui a qualifié la mesure
--
-- Nouveau fichier de migration, même règle et même forme que 03, 05
-- et 06. À appliquer à la main sur les bases déjà démarrées :
--
--   psql -U enervision -d enervision -f 07_mesure_quality_source.sql
--
-- LE PROBLÈME QU'ELLE RÉSOUT
-- --------------------------
-- data_quality est NOT NULL DEFAULT 'good' avec un CHECK sur quatre
-- valeurs : le schéma figé ne sait pas dire « pas encore qualifiée ».
-- Le collecteur, qui écrit le premier, retombe donc sur 'good' quand
-- la source se tait (collector/sink.py, constante UNQUALIFIED), et
-- l'ETL repose la vraie qualification à son passage.
--
-- Entre les deux, une mesure porte un 'good' que rien n'atteste. Ce
-- n'était jusqu'ici qu'une gêne interne à la chaîne. Cela devient un
-- faux chiffre dès que l'API publie la proportion de mesures
-- dégradées par site : une journée fraîchement collectée, non encore
-- traitée par l'ETL, affiche 0 % de dégradation et le site paraît
-- parfait. C'est l'inverse de ce que l'indicateur doit dire.
--
-- Aucune colonne existante ne permettait de le voir. inserted_at
-- date l'entrée de la ligne, pas son passage en ETL ; imputation_method
-- vaut 'none' aussi bien avant l'ETL qu'après lui sur une mesure
-- saine. La distinction n'était donc pas reconstructible.
--
-- POURQUOI UNE COLONNE, ET NON UN JOURNAL DE RUN ETL
-- --------------------------------------------------
-- Un journal par (site, jour) dirait la même chose, mais à côté de
-- la donnée : il faudrait le joindre, et il vieillirait séparément.
-- La colonne voyage avec la mesure, et elle est reposée par le
-- DO UPDATE de l'ETL (etl/load.py, DERIVED_COLUMNS) : rejouer une
-- fenêtre après correction d'une règle remet la marque à jour du
-- même geste, ce qui est exactement le comportement voulu.
--
-- DÉFAUT 'source', ET NON 'etl'
-- -----------------------------
-- Les lignes déjà en base prennent 'source'. Certaines ont pourtant
-- déjà été traitées par l'ETL, et se trouvent donc sous-déclarées.
-- C'est le sens conservateur, et c'est celui qu'il faut : sous-
-- déclarer la couverture fait dire à l'indicateur « je ne sais pas
-- encore », sur-déclarer lui ferait affirmer une qualité que rien ne
-- garantit. Un rejeu de l'ETL sur la fenêtre concernée corrige la
-- marque sans rien changer d'autre.
--
-- PAS D'INDEX
-- -----------
-- Le comptage se fait sur une fenêtre de temps d'un site, que la clé
-- primaire (site_id, ts) couvre déjà. Un index sur une valeur portée
-- par la quasi-totalité des lignes ne serait pas emprunté.
--
-- IDEMPOTENT : rejouable sur une base déjà à jour.
-- ============================================================

ALTER TABLE mesure
    ADD COLUMN IF NOT EXISTS quality_source VARCHAR(10) NOT NULL
        DEFAULT 'source';

ALTER TABLE mesure
    DROP CONSTRAINT IF EXISTS mesure_quality_source_check;

ALTER TABLE mesure
    ADD CONSTRAINT mesure_quality_source_check
    CHECK (quality_source IN ('source', 'etl'));

COMMENT ON COLUMN mesure.quality_source IS
    'Qui a pose data_quality et null_reasons : source pour la valeur ecrite'
    ' par le collecteur, qui retombe sur le defaut good quand la source se'
    ' tait ; etl quand la qualification a ete deduite des donnees. Une'
    ' fenetre encore en source n''est pas une fenetre saine, c''est une'
    ' fenetre non qualifiee.';
