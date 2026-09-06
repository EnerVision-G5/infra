# Monitoring

Prometheus, Grafana, Loki + Promtail, node-exporter, cAdvisor.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- Composition de la stack, réseau monitoring_network, volumes
- Datasources et dashboards provisionnés (Node Exporter, cAdvisor, Traefik)
- Collecte des logs (Promtail → Loki) vs métriques (Prometheus)
- Rétention (Prometheus, Loki 168h)
- Point d'attention cAdvisor : version + containerd-snapshotter — renvoi vers Exploitation
