# L'hôte

La machine qui porte tout : caractéristiques et contraintes qui ont un impact sur l'infra.

!!! note "Ébauche — phase 1"
    Cette page sera rédigée dans une phase ultérieure. Plan prévu :

- VM Proxmox, CPU/RAM, GPU nvidia (runtime Docker par défaut)
- Docker : driver de stockage overlay2 vs snapshotter containerd, /etc/docker/daemon.json géré à la main
- OS, accès (SSH root + mot de passe via Vault), pare-feu géré hors Ansible
- Ce qu'Ansible ne touche pas : paquets, SSH, firewall, daemon.json
