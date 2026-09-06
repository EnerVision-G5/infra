# Front (dashboard)

L'image statique du dashboard React, servie par Nginx derrière Traefik.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Image dashboard, réseau proxy_network
- Config au runtime : /config.js généré au démarrage (API_BASE_URL, CSP connect-src, PREDICTION_SOURCE)
- Pourquoi pas de config au build : une image réutilisable entre environnements
- Dépannage : variable API introuvable, CORS, CSP — renvoi vers Exploitation
