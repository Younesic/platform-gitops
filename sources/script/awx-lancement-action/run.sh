#!/usr/bin/env bash
# ACTION — `run.sh` SEUL : « une exécution qui se termine ; supprimer la demande ne
# défait rien ». Cette classe vient de la PRÉSENCE de ce fichier (et de l'absence de
# apply/destroy) : elle ne se déclare nulle part, donc elle ne peut pas mentir.
#
# Le plugin choisit CE dossier quand le survey du job template ne porte AUCUNE
# variable d'état — c'est-à-dire quand le geste ne sait pas se défaire.
set -euo pipefail
exec bash ./lancer.sh
