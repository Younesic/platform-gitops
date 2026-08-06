#!/usr/bin/env bash
# RESSOURCE AWX, verbe OBSERVE (CD9) — lance le MÊME job template en `job_type:
# check` : Ansible simule avec l'état `present` et RAPPORTE ce qui divergerait,
# sans toucher la cible. C'est le « lire sans écrire » de ce moteur.
#
# Ce fichier n'est atteint QUE si l'offre est adoptable — ce que la génération
# gate sur `ask_job_type_on_launch: true` du template (le verrou s'exécute :
# jamais un Observé décoratif).
set -euo pipefail
ETAT=present CHECK=1 exec bash ./lancer.sh
