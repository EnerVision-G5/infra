# Garage (stockage objet S3)

Stockage compatible S3 pour les artefacts MLflow et les archives, + endpoint web et UI.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Image, volumes (metadata / data / snapshots), réseaux
- garage.toml : replication_factor, s3_api, s3_web, admin
- Bootstrap du layout (obligatoire, sinon 503) — renvoi vers Exploitation
- Buckets & clés, garage-webui
- Dépannage : 503 quorum, 404 web
