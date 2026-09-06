# Traefik

Point d'entrée HTTP unique : routage, terminaison TLS, métriques. Découvre
les autres conteneurs par leurs **labels Docker**.

| | |
|---|---|
| Rôle Ansible | `traefik` (`provision.yml`) |
| Image | `traefik:v3.7.9` |
| Dossier hôte | `/opt/srv/traefik/` |
| Réseaux | `proxy_network`, `monitoring_network` |
| Volume | `traefik_letsencrypt` (stockage `acme.json`) |
| Ports publiés | `80` (`web`), `443` (`websecure`) |

## Configuration

Tout est en `command:` dans le compose (pas de fichier statique) :

- **Provider Docker** : `exposedbydefault=false` → un conteneur n'est routé
  que s'il porte `traefik.enable=true`.
- **Entrypoints** : `web` (:80), `websecure` (:443), `metrics` (:8082).
- **Métriques Prometheus** sur l'entrypoint `metrics`, avec labels de
  routeurs et de services. Scrapées par Prometheus (`traefik:8082`).
- **ACME Let's Encrypt** : résolveur `letsencrypt` configuré (challenge HTTP
  sur `web`, contact `acme_email`) — mais **attaché à aucun routeur**
  aujourd'hui.
- **Tableau de bord** : `--api.dashboard=true`, `--api.insecure=false`.
  Routé sur `traefik.enervision.com`, entrypoint `websecure`, `tls=true`
  (certificat auto-signé faute de resolver attaché).

`.env` : `TRAEFIK_DOMAIN`, `ACME_EMAIL`.

## Comment un service se déclare

Dans le `compose.yml` du service, en labels :

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=proxy_network"
  - 'traefik.http.routers.<nom>.rule=Host(`<domaine>`)'
  - "traefik.http.routers.<nom>.entrypoints=web"     # {{ traefik_entrypoint }}
  - "traefik.http.routers.<nom>.service=<nom>"
  - "traefik.http.services.<nom>.loadbalancer.server.port=<port interne>"
  # - "traefik.http.routers.<nom>.tls=true"                    # commenté
  # - "traefik.http.routers.<nom>.tls.certresolver=letsencrypt" # commenté
```

Le conteneur **doit** être sur `proxy_network` et Traefik aussi.

## État HTTPS

`traefik_entrypoint` = `web` → tout le trafic applicatif est en **HTTP :80**.
Passer en HTTPS : [runbook DNS & TLS](../exploitation/dns-tls.md).

## Dépannage

| Symptôme | Piste |
|---|---|
| `404 page not found` | le service n'a pas `traefik.enable=true`, ou pas la règle `Host()`, ou pas sur `proxy_network` |
| Route absente du tableau de bord | Traefik ne voit pas le conteneur : vérifier `docker inspect` les labels, et `traefik.docker.network` |
| Certificat auto-signé | normal aujourd'hui — aucun resolver TLS n'est attaché |
| Métriques Traefik absentes de Grafana | Prometheus doit joindre `traefik:8082` → Traefik doit être sur `monitoring_network` |

```bash
docker logs traefik --tail 50
docker exec traefik traefik version
# routeurs vus par Traefik :
curl -s http://localhost/api/http/routers | python3 -m json.tool   # via tunnel/tableau de bord
```
