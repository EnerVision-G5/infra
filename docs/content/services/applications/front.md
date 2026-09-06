# front — le dashboard

Application monopage React, compilée, servie en statique par Nginx.

| | |
|---|---|
| `kind` | `web` |
| Image | `ghcr.io/enervision-g5/dashboard:<sha>` (dépôt `dashboard`) |
| Conteneur | `enervision-front` |
| Réseau | `proxy_network` |
| Port interne | `8080` (nginx-unprivileged tourne en uid 101, ne peut pas prendre un port < 1024) |
| Route | `app.enervision.com` |
| Volume | aucun |

## Configuration au runtime — `/config.js`

!!! important "Rien n'est figé au build"
    L'image est construite une fois par commit. Au **démarrage du
    conteneur**, un script génère `/config.js` à partir des variables du
    `.env`, et le dashboard le lit avant de démarrer.

`.env` généré (`front.env.j2`) — **aucun secret**, ces valeurs sont
republiées en clair dans `/config.js` :

| Clé | Vient de | Rôle |
|---|---|---|
| `API_BASE_URL` | `applications_front_api_base_url` | hôte **public** de l'API, tel que le navigateur la joint (`http://api.enervision.com`) |
| `CSP_CONNECT_SRC` | `applications_front_csp_connect_src` | origines que le navigateur a le droit d'appeler (directive CSP `connect-src`) |
| `PREDICTION_SOURCE` | `applications_front_prediction_source` | `api` (défaut) ou `fixture` |

`API_BASE_URL` et `CSP_CONNECT_SRC` **dérivent** des hôtes déjà déclarés et du
schéma (`applications_public_scheme`, `http` tant que Traefik est en `web`) :
aucun domaine n'est écrit deux fois.

## CORS + CSP : symétrie avec l'API

- Le front pose `CSP_CONNECT_SRC` → le navigateur **autorise l'émission** de
  l'appel vers l'API.
- L'API pose `CORS_ALLOWED_ORIGINS` → le navigateur **autorise la lecture** de
  la réponse.

Il faut **les deux**, et les deux origines doivent être écrites à
l'identique (schéma + hôte). Les deux dérivent des mêmes variables
(`applications_*_host`, `applications_public_scheme`) : une seule source, pas
de risque de décalage.

## Asserts du rôle

Le déploiement échoue si `applications_front_csp_connect_src` est vide ou
contient un joker, ou si `applications_front_api_base_url` est vide.

## Dépannage

| Symptôme | Cause |
|---|---|
| page blanche « erreur de configuration » | `API_BASE_URL` vide ou `/config.js` non généré |
| appels API bloqués par le navigateur (console : *blocked by CORS* / *CSP*) | origine du front absente de `CORS_ALLOWED_ORIGINS` (API) **ou** de `CSP_CONNECT_SRC` (front), ou schéma qui diffère (`http` vs `https`) |
| `404` sur une route du dashboard | fallback SPA non configuré côté image — problème du dépôt `dashboard`, pas de l'infra |

La configuration effective est servie sur `/config.js`
(`http://app.enervision.com/config.js`).
