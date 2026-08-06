#!/usr/bin/env bash
# RESSOURCE, verbe APPLY — lance le job template avec la variable d'état à `present`.
# Le pendant `destroy.sh` la pose à `absent` : c'est le MÊME job template, et c'est
# précisément ce que le moteur ansible abandonné savait faire réellement — sans la
# réconciliation périodique qu'il promettait sans la tenir.
set -euo pipefail
ETAT=present exec bash ./lancer.sh
