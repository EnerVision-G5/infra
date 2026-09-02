-- ============================================================
-- EV-08 — Colonnes d'imputation sur `mesure`
--
-- Ce fichier appartient au repo de la base (enervision-db). Il est
-- déposé ici parce que l'ETL est le seul à écrire ces deux colonnes,
-- et qu'il ne peut rien charger tant qu'elles n'existent pas. À
-- reporter tel quel dans enervision-db/initdb/03_mesure_imputation.sql,
-- puis à appliquer sur les bases déjà démarrées, dont les scripts
-- d'initdb ne sont plus rejoués :
--
--   psql -U enervision -d enervision -f 03_mesure_imputation.sql
--
-- Le schéma figé v1.0 reste intact : sa règle d'évolution impose un
-- nouveau fichier de migration, jamais l'édition de 01_schema.sql.
--
-- Ces colonnes ne sont pas une extension locale de l'équipe Data : le
-- contrat gelé entre les équipes les déclare déjà, sur
-- EnergyReadingOut.consumption_kw_imputed et
-- EnergyReadingOut.imputation_method, dans
-- enervision/docs/contracts/openapi-api.json. L'API ne peut pas les
-- servir tant que la base ne les porte pas.
--
-- La valeur brute n'est jamais touchée : consumption_kw reste ce que
-- la source a envoyé, y compris NULL. C'est tout l'objet du ticket.
-- ============================================================

-- Idempotent : la migration peut être rejouée sur une base déjà à jour
-- sans faire échouer un redémarrage de la pile.
ALTER TABLE mesure
    ADD COLUMN IF NOT EXISTS consumption_kw_imputed NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS imputation_method VARCHAR(20) NOT NULL
        DEFAULT 'none';

ALTER TABLE mesure
    DROP CONSTRAINT IF EXISTS mesure_imputation_method_check;

-- Mêmes valeurs que l'énumération ImputationMethod du contrat gelé.
ALTER TABLE mesure
    ADD CONSTRAINT mesure_imputation_method_check
    CHECK (imputation_method IN ('none', 'locf', 'interpolation'));

COMMENT ON COLUMN mesure.consumption_kw_imputed IS
    'Meilleure valeur exploitable : la valeur brute si elle existe, la valeur'
    ' reconstruite par l''ETL sinon. NULL quand rien ne permettait de la'
    ' reconstruire.';

COMMENT ON COLUMN mesure.imputation_method IS
    'Provenance de consumption_kw_imputed : none (valeur brute, ou rien à'
    ' reconstruire), locf (report de la dernière valeur connue),'
    ' interpolation (encadrée par deux valeurs connues).';

-- Audit des valeurs reconstruites : combien, où, par quelle méthode.
-- Index partiel, parce que la très grande majorité des mesures n'est
-- pas imputée et n'a rien à faire dans cet index.
CREATE INDEX IF NOT EXISTS idx_mesure_imputation
    ON mesure (site_id, ts DESC)
    WHERE imputation_method <> 'none';
