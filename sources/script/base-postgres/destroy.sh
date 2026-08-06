#!/usr/bin/env bash
# base-postgres/destroy.sh — la destruction PILOTÉE (le verbe du pipeline delete).
#
# GARDES : on ne détruit que CE QUI EST À NOUS (base possédée par le propriétaire
# déclaré — sinon REFUS) ; idempotent (déjà absente = rien à faire, exit 0 — un
# pipeline delete peut re-tourner) ; le rôle n'est retiré que s'il ne possède
# plus RIEN d'autre (un propriétaire partagé par deux bases survit à la première).
set -euo pipefail

: "${SPEC_NOM:?champ nom requis}"
: "${SPEC_PROPRIETAIRE:?champ proprietaire requis}"
: "${PGHOST:?identifiants Postgres absents (credsSecret)}"

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -v nom="$SPEC_NOM" -v prop="$SPEC_PROPRIETAIRE")
# ⚠️ psql N'INTERPOLE PAS les variables -v dans un `-c` : le :'var' littéral part
# au serveur (attrapé au rejeu local). L'interpolation ne joue que sur STDIN —
# d'où ces deux aides : q = requête (valeur), x = ordre.
q() { printf '%s\n' "$1" | "${PSQL[@]}" -tA; }
x() { printf '%s\n' "$1" | "${PSQL[@]}"; }

DB_OWNER=$(q "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = :'nom'")
if [ -z "$DB_OWNER" ]; then
  echo "base ${SPEC_NOM} : déjà absente, rien à faire"
elif [ "$DB_OWNER" != "$SPEC_PROPRIETAIRE" ]; then
  echo "REFUS : la base ${SPEC_NOM} appartient à « ${DB_OWNER} », pas à" >&2
  echo "        « ${SPEC_PROPRIETAIRE} » — on ne détruit pas ce qui n'est pas à nous." >&2
  exit 1
else
  # WITH (FORCE) : coupe les connexions restantes — sans lui un client oublié
  # bloquerait la destruction (et donc le finalizer du claim) indéfiniment.
  x 'DROP DATABASE :"nom" WITH (FORCE)'
  echo "base ${SPEC_NOM} : détruite"
fi

RESTE=$(q "SELECT count(*) FROM pg_database WHERE pg_get_userbyid(datdba) = :'prop'")
ROLE_EXISTE=$(q "SELECT count(*) FROM pg_roles WHERE rolname = :'prop'")
if [ "$ROLE_EXISTE" != "0" ] && [ "$RESTE" = "0" ]; then
  x 'DROP ROLE :"prop"'
  echo "rôle ${SPEC_PROPRIETAIRE} : retiré (ne possédait plus rien)"
elif [ "$ROLE_EXISTE" != "0" ]; then
  echo "rôle ${SPEC_PROPRIETAIRE} : conservé (possède encore ${RESTE} base(s))"
else
  echo "rôle ${SPEC_PROPRIETAIRE} : déjà absent"
fi

{
  echo "base=${SPEC_NOM}"
  echo "etat=detruite"
} >> "$SORTIES"
