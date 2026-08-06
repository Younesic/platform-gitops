#!/usr/bin/env bash
# base-postgres — le verbe OBSERVE (barreau Observé de l'adoption, CD9).
#
# GARANTIE (gelée) : « la plateforme lit et compare, ne modifie rien. »
# Ce script est en LECTURE SEULE — psql en SELECT uniquement. Sa présence est ce
# qui rend l'offre ADOPTABLE : la capacité se déduit de ce fichier, personne ne
# coche une case (§9quater, bloc « L'échelle d'adoption »).
#
# Il relève l'état RÉEL et le porte au status ; l'écart avec le DÉCLARÉ est dit
# champ par champ. Une absence est un fait relevé, pas une erreur : « la base
# n'existe pas » est exactement ce que le demandeur veut savoir avant de confier.
set -euo pipefail

: "${SPEC_NOM:?champ nom requis}"
: "${PGHOST:?identifiants Postgres absents (credsSecret)}"

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -v nom="$SPEC_NOM")
# ⚠️ psql n'interpole pas -v dans un `-c` : STDIN seulement (gotcha payé en CD3).
q() { printf '%s\n' "$1" | "${PSQL[@]}" -tA; }

PROPRIETAIRE_REEL=$(q "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = :'nom'")
if [ -z "$PROPRIETAIRE_REEL" ]; then
  echo "relevé : la base ${SPEC_NOM} N'EXISTE PAS sur ${PGHOST}"
  {
    echo "existe=false"
    echo "hote=${PGHOST}"
  } >> "$SORTIES"
  exit 0
fi

COMMENTAIRE_REEL=$(q "SELECT coalesce(shobj_description(oid, 'pg_database'), '') FROM pg_database WHERE datname = :'nom'")
echo "relevé : base ${SPEC_NOM} · propriétaire réel « ${PROPRIETAIRE_REEL} » · commentaire réel « ${COMMENTAIRE_REEL} »"

# ── L'écart avec le DÉCLARÉ, champ par champ — le signal que le demandeur attend ──
ECARTS=""
if [ -n "${SPEC_PROPRIETAIRE:-}" ] && [ "$PROPRIETAIRE_REEL" != "$SPEC_PROPRIETAIRE" ]; then
  ECARTS="${ECARTS}proprietaire "
fi
if [ -n "${SPEC_COMMENTAIRE:-}" ] && [ "$COMMENTAIRE_REEL" != "${SPEC_COMMENTAIRE}" ]; then
  ECARTS="${ECARTS}commentaire "
fi

{
  echo "existe=true"
  echo "proprietaireReel=${PROPRIETAIRE_REEL}"
  echo "commentaireReel=${COMMENTAIRE_REEL}"
  echo "hote=${PGHOST}"
  if [ -n "$ECARTS" ]; then
    echo "ecart=${ECARTS% }"
  else
    echo "ecart=aucun"
  fi
} >> "$SORTIES"
[ -n "$ECARTS" ] && echo "écart avec le déclaré : ${ECARTS% }" || echo "aligné au déclaré"
