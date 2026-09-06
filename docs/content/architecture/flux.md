# Flux applicatifs

Comment circule une requête, de bout en bout, pour les scénarios principaux.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Séquence : connexion + appel API authentifié (navigateur → Traefik → front → api → TimescaleDB)
- Séquence : prédiction (front → api → serving → features Garage + modèle MLflow)
- Séquence : ingestion (poller collector → API Mock IoT → TimescaleDB ; rattrapage par timer)
- Séquence : entraînement (timer → training → MLflow/Garage → serving résout l'alias du modèle)
