#!/usr/bin/env bash
# ACTION « lancer une analyse de vulnérabilités » — pilote OA3 du moteur `api`.
#
# LA CLASSE VIENT DES OPÉRATIONS : la désignation ne porte QU'UNE opération de
# création (`POST /api/v1/finding/project/{uuid}/analyze`). Pas de read, pas de
# delete ⇒ il n'y a rien à posséder ⇒ c'est une ACTION, et sa garantie est celle
# des actions : « la plateforme exécute et rend compte · ne surveille rien ·
# supprimer la demande ne défait rien ».
#
# Ce fichier est le VERBE `run` du moteur script (§9quater) : sa seule présence
# déclare la classe. Le runner partagé lui donne SPEC_<CHAMP> et $SORTIES.
#
# ⚠️ La clé d'API n'apparaît JAMAIS dans une commande imprimée : le runner trace
# ce qu'il exécute, donc l'en-tête est construit depuis un fichier de
# configuration curl, pas passé en argument visible.
set -euo pipefail

: "${SPEC_PROJETUUID:?champ projetUuid requis}"
: "${DTRACK_URL:?identifiants Dependency-Track absents (credsSecret)}"
: "${DTRACK_API_KEY:?identifiants Dependency-Track absents (credsSecret)}"

CONF="$(mktemp)"
trap 'rm -f "$CONF"' EXIT
printf 'header = "X-Api-Key: %s"\n' "$DTRACK_API_KEY" > "$CONF"

URL="${DTRACK_URL%/}/api/v1/finding/project/${SPEC_PROJETUUID}/analyze"
echo "lancement d'une analyse sur le projet ${SPEC_PROJETUUID}"

CORPS="$(mktemp)"
CODE="$(curl -sS -K "$CONF" -o "$CORPS" -w '%{http_code}' -X POST "$URL")"

case "$CODE" in
  200|202)
    ;;
  404)
    echo "ECHEC : aucun projet Dependency-Track ne porte l'identifiant ${SPEC_PROJETUUID}." >&2
    echo "        L'action ne crée rien : elle agit sur un projet qui doit EXISTER." >&2
    echo "        Vérifier l'UUID (la fiche du projet le porte en sortie)." >&2
    exit 1
    ;;
  *)
    echo "ECHEC : Dependency-Track a refusé le lancement (HTTP ${CODE})." >&2
    head -c 400 "$CORPS" >&2 || true
    exit 1
    ;;
esac

JETON="$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CORPS" | head -1)"

{
  echo "resultat=lancee"
  echo "projet=${SPEC_PROJETUUID}"
  [ -n "$JETON" ] && echo "reference=${JETON}"
  # Le lien rendu au demandeur pointe l'adresse PUBLIQUE (l'interne ne s'ouvre
  # que depuis le cluster) ; on retombe sur l'interne si elle n'est pas déclarée.
  echo "journal=${DTRACK_PUBLIC_URL:-$DTRACK_URL}"
  echo "projetUrl=${DTRACK_PUBLIC_URL:-${DTRACK_URL%/}}/projects/${SPEC_PROJETUUID}/findings"
} >> "$SORTIES"

echo "analyse lancée (HTTP ${CODE})${JETON:+ · jeton de suivi ${JETON}}"
