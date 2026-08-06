#!/usr/bin/env bash
# base-postgres — RESSOURCE (contrat déclaré, §9quater) : une base + son rôle
# propriétaire sur une instance Postgres EXISTANTE, via psql.
#
# GARANTIE de la classe (gelée) : « Converge au changement déclaré · destruction
# pilotée · pas d'auto-guérison. » — pas d'observe.sh : aucune surface de dérive.
#
# IDEMPOTENT par GARDES (sa moitié du contrat) : re-run sans changement = zéro
# effet, et le journal le DIT. Une base existante qui n'appartient pas au
# propriétaire déclaré = REFUS (la plateforme ne s'approprie rien).
#
# Identifiants : PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE par l'ENVIRONNEMENT
# (credsSecret) — jamais en argument. Les identifiants SQL sont bornés par le
# PATTERN du contrat ET cités côté psql (défense en profondeur).
set -euo pipefail

: "${SPEC_NOM:?champ nom requis}"
: "${SPEC_PROPRIETAIRE:?champ proprietaire requis}"
: "${PGHOST:?identifiants Postgres absents (credsSecret)}"
COMMENTAIRE="${SPEC_COMMENTAIRE:-}"

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -v nom="$SPEC_NOM" -v prop="$SPEC_PROPRIETAIRE")
# ⚠️ psql N'INTERPOLE PAS les variables -v dans un `-c` : le :'var' littéral part
# au serveur (attrapé au rejeu local). L'interpolation ne joue que sur STDIN —
# d'où ces deux aides : q = requête (valeur), x = ordre.
q() { printf '%s\n' "$1" | "${PSQL[@]}" -tA; }
x() { printf '%s\n' "$1" | "${PSQL[@]}"; }

# ── Le rôle propriétaire (NOLOGIN : il possède, il ne se connecte pas) ─────────
ROLE_EXISTE=$(q "SELECT count(*) FROM pg_roles WHERE rolname = :'prop'")
if [ "$ROLE_EXISTE" = "0" ]; then
  x 'CREATE ROLE :"prop" NOLOGIN'
  echo "rôle ${SPEC_PROPRIETAIRE} : créé"
else
  echo "rôle ${SPEC_PROPRIETAIRE} : déjà en place, rien à faire"
fi
# Créer une base POUR ce rôle exige d'en être membre (PG) — grant idempotent,
# légal parce que CREATEROLE nous donne ADMIN sur les rôles que nous créons.
x 'GRANT :"prop" TO CURRENT_USER' >/dev/null 2>&1 || true

# ── La base : absente = créer · à nous = converger · à un autre = REFUS ────────
DB_OWNER=$(q "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = :'nom'")
if [ -z "$DB_OWNER" ]; then
  x 'CREATE DATABASE :"nom" OWNER :"prop"'
  echo "base ${SPEC_NOM} : créée (propriétaire ${SPEC_PROPRIETAIRE})"
elif [ "$DB_OWNER" != "$SPEC_PROPRIETAIRE" ]; then
  echo "REFUS : la base ${SPEC_NOM} existe déjà et appartient à « ${DB_OWNER} »," >&2
  echo "        pas à « ${SPEC_PROPRIETAIRE} » — la plateforme ne s'approprie pas" >&2
  echo "        l'existant (choisir un autre nom, ou le bon propriétaire)." >&2
  exit 1
else
  echo "base ${SPEC_NOM} : déjà en place, rien à faire"
fi

# ── Le commentaire : le champ de convergence — écrit SEULEMENT s'il diffère ────
ACTUEL=$(q "SELECT coalesce(shobj_description(oid, 'pg_database'), '') FROM pg_database WHERE datname = :'nom'")
if [ "$ACTUEL" != "$COMMENTAIRE" ]; then
  "${PSQL[@]}" -v com="$COMMENTAIRE" <<'SQL'
COMMENT ON DATABASE :"nom" IS :'com';
SQL
  echo "commentaire : convergé au déclaré"
else
  echo "commentaire : déjà au déclaré, rien à faire"
fi

{
  echo "base=${SPEC_NOM}"
  echo "proprietaire=${SPEC_PROPRIETAIRE}"
  echo "hote=${PGHOST}"
  echo "etat=en place"
} >> "$SORTIES"
