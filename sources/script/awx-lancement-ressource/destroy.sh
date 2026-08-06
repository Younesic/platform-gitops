#!/usr/bin/env bash
# RESSOURCE, verbe DESTROY — la contrepartie honnête d'apply : supprimer la demande
# lance le MÊME job template avec l'état `absent`. Sans ce fichier, la migration des
# produits ansible en « actions » PERDRAIT la destruction : un recul déguisé en
# garantie plus honnête.
set -euo pipefail
ETAT=absent exec bash ./lancer.sh
