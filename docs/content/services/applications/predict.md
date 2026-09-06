# Predict (serving, training, MLflow, ETL, collector)

La chaîne de prédiction : plusieurs services issus du dépôt predict.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- serving (web), training (job/timer), mlflow (web, sur l'image training)
- collector (worker) + rattrapage nocturne (timer systemd)
- etl (worker)
- Variables : MOCK_API_URL, stockage Garage, MLflow tracking URI
- Timers systemd : collector-backfill, training — installés/retirés par le rôle
