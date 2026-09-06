# Domaines & routage

Toutes les routes passent par Traefik. Le domaine racine est
`enervision.com` ; chaque enregistrement DNS doit **résoudre vers l'IP de la
VM** avant le déploiement, sinon Traefik n'a aucun `Host` à faire
correspondre.

## Table des routes

| Domaine | Service | Conteneur | Port interne | Entrypoint | Auth |
|---|---|---|---|---|---|
| `app.enervision.com` | dashboard | `enervision-front` | 8080 | `web` | — |
| `api.enervision.com` | API métier | `enervision-api` | 8080 | `web` | JWT |
| `predict.enervision.com` | service d'inférence | `enervision-serving` | 8000 | `web` | — *(appelé par l'API)* |
| `grafana.enervision.com` | Grafana | `grafana` | 3000 | `web` | login Grafana |
| `s3.enervision.com` + `*.s3.enervision.com` | Garage — API S3 | `garage` | 3900 | `web` | clés S3 |
| `web.enervision.com` + `*.web.enervision.com` | Garage — hébergement statique | `garage` | 3902 | `web` | selon bucket |
| `garage.enervision.com` | Garage — interface web | `garage-webui` | 3909 | `web` | jeton admin |
| `mlflow.enervision.com` | registre MLflow *(si `applications_mlflow_expose`)* | `enervision-mlflow` | 5000 | `web` | **basicauth** (htpasswd, Vault) |
| `traefik.enervision.com` | tableau de bord Traefik | `traefik` | *(api@internal)* | `websecure` | — |

Les wildcards `*.s3.` et `*.web.` viennent du fonctionnement de Garage :
`<bucket>.web.enervision.com` sert le bucket `<bucket>`. Voir
[Services › Garage](../services/garage.md).

## Schéma vs HTTPS

`traefik_entrypoint` vaut **`web`** → tout le trafic applicatif est en
**HTTP sur le port 80**. Le port 443 (`websecure`) existe mais :

- un résolveur ACME Let's Encrypt est configuré dans Traefik **mais n'est
  attaché à aucun routeur** (labels `tls.certresolver` commentés) ;
- seul le routeur du tableau de bord Traefik demande `tls=true` → certificat
  auto-signé par défaut.

La variable `applications_public_scheme` suit cet état : elle vaut `http`
tant que l'entrypoint est `web`, et les origines CORS / CSP en découlent
automatiquement. Passer en HTTPS = changer `traefik_entrypoint` en
`websecure` **et** décommenter les labels TLS des routeurs — voir le
[runbook DNS & TLS](../exploitation/dns-tls.md).

## Enregistrements DNS attendus

Un `A`/`AAAA` par domaine du tableau ci-dessus, tous vers l'IP de la VM,
plus deux wildcards :

```
app        A   <ip-vm>
api        A   <ip-vm>
predict    A   <ip-vm>
grafana    A   <ip-vm>
garage     A   <ip-vm>
mlflow     A   <ip-vm>
traefik    A   <ip-vm>
s3         A   <ip-vm>
*.s3       A   <ip-vm>
web        A   <ip-vm>
*.web      A   <ip-vm>
```
