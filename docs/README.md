# Documentation de l'infrastructure

Site MkDocs Material. Pour l'instant : **local uniquement, via Docker.**

```bash
cd docs
docker compose up            # http://localhost:8000  (rechargement à chaud)
```

Port 8000 déjà pris (autre projet) ? Éditer `ports:` dans `compose.yml`.

Build de contrôle (comme le fera la CI plus tard) — le `--user` évite que le
conteneur écrive `site/` en root :

```bash
cd docs
docker compose run --rm --user "$(id -u):$(id -g)" docs build --strict
```

## Organisation

| Chemin | Rôle |
|---|---|
| `docs/mkdocs.yml` | configuration du site |
| `docs/content/` | **le contenu** (Markdown) |
| `docs/content/**/.nav.yml` | ordre et titres de la navigation (plugin *awesome-nav*) |
| `docs/Dockerfile`, `docs/compose.yml`, `docs/requirements.txt` | la stack qui sert le site |
| `docs/site/` | build, **ignoré par Git** |

## Ajouter / modifier une page

1. Créer ou éditer un `.md` sous `docs/content/…`.
2. Si besoin, l'ajouter au `.nav.yml` du dossier.
3. `docker compose up` montre le résultat en direct.

## Sans Docker (optionnel)

```bash
pip install -r docs/requirements.txt
mkdocs serve -f docs/mkdocs.yml
```
