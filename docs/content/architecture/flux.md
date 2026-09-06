# Flux applicatifs

Comment circule une requête, pour les scénarios principaux. Le détail des
services : [Services › Applications](../services/applications/index.md).

## Consultation du dashboard + appel API

Le navigateur charge le dashboard depuis `app.enervision.com`, puis lit sa
configuration dans `/config.js` (générée au démarrage du conteneur `front`),
et appelle l'API sur son **hôte public** `api.enervision.com` — pas le nom de
conteneur, c'est le poste de l'utilisateur qui émet l'appel.

```mermaid
sequenceDiagram
    participant B as Navigateur
    participant T as Traefik
    participant F as front (nginx)
    participant A as api
    participant D as TimescaleDB

    B->>T: GET app.enervision.com/
    T->>F: proxy_network
    F-->>B: index.html + /config.js (API_BASE_URL, CSP)
    B->>T: POST api.enervision.com/auth/token
    Note over B,T: CORS + CSP connect-src doivent autoriser<br/>l'origine du front
    T->>A: proxy_network
    A->>D: db_network — vérifie l'utilisateur (argon2id)
    A-->>B: JWT
    B->>A: GET /sites (Authorization: Bearer …)
    A->>D: lecture
    A-->>B: données
```

CORS (côté API) et CSP `connect-src` (côté front) sont **symétriques** : l'un
autorise l'émission de la requête, l'autre la lecture de la réponse. Voir le
[runbook configuration du front](../exploitation/front-config.md).

## Prédiction

L'API délègue l'inférence au service `serving`, qui résout un alias du
registre MLflow et relit les partitions de variables produites par l'ETL sur
Garage.

```mermaid
sequenceDiagram
    participant A as api
    participant S as serving
    participant M as MLflow
    participant G as Garage (S3)

    A->>S: POST /predict (ml_network)
    S->>M: résout models:/enervision_xgboost@champion
    M-->>S: version + URI d'artefact
    S->>G: lit les partitions de features (storage_network)
    S-->>A: série prédite
    A->>A: archive dans la table `prediction`
```

Si MLflow est injoignable, `serving` **démarre quand même** mais répond
`503` — visible dans son journal et sur sa sonde.

## Ingestion des mesures

Le `collector` (poller) interroge l'API Mock IoT en continu et écrit dans la
table `mesure`. Un timer systemd rejoue chaque nuit une fenêtre glissante
(`--days 2`) pour combler un éventuel trou.

```mermaid
sequenceDiagram
    participant P as collector (poller)
    participant K as API Mock IoT
    participant D as TimescaleDB
    participant E as etl

    loop en continu
        P->>K: GET /current (chaque site)
        K-->>P: mesures
        P->>D: INSERT ... ON CONFLICT DO NOTHING
    end
    Note over T: Timer collector-backfill — chaque nuit 02:30
    loop toutes les heures
        E->>D: lit les mesures trouées
        E->>D: écrit les colonnes d'imputation + `mesure_exclu`
    end
```

## Réentraînement

Traitement daté, déclenché par un timer systemd hebdomadaire — jamais par un
`docker compose up`.

```mermaid
sequenceDiagram
    participant Ti as timer systemd (dim. 03:30)
    participant Tr as training (job)
    participant G as Garage (S3)
    participant M as MLflow

    Ti->>Tr: docker compose --profile jobs run --rm training --history-days 90
    Tr->>G: lit 90 j de partitions de variables
    Tr->>Tr: entraîne (XGBoost)
    Tr->>M: enregistre une nouvelle version (challenger)
    Tr-->>Ti: exit 0
    Note over M: La promotion est un geste manuel :<br/>docker compose --profile jobs run --rm training --promote-version <n>
```
