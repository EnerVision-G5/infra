# Image de la documentation : mkdocs-material officiel + le plugin awesome-nav.
# L'image de base porte déjà mkdocs, mkdocs-material et pymdown-extensions ;
# requirements.txt réépingle mkdocs-material à la même version et ajoute
# awesome-nav, absent de l'image.
FROM squidfunk/mkdocs-material:9.7.7

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# L'entrypoint de l'image de base est déjà `mkdocs`, le workdir est /docs.
# compose.yml monte docs/ sur /docs et passe la commande `serve`.
