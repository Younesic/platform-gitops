#!/usr/bin/env bash
# Le lanceur AWX — fourni par la PLATEFORME, jamais par le fournisseur.
#
# Une action AWX est une promesse `script` (§9quater) dont le contrat vient d'un
# SURVEY au lieu d'un fichier, et dont les verbes sont ces scripts-ci. Rien de neuf
# côté moteur : le runner partagé, le pin de gouvernance, les SPEC_*, $SORTIES —
# tout est celui de CD2/CD3.
#
# Ce que la PROMESSE pose dans l'environnement (jamais la demande) :
#   AWX_URL           l'API interne d'AWX
#   AWX_WEB           l'URL publique, pour le lien vers le journal
#   AWX_JOB_TEMPLATE  le SEUL job template lançable (déclaré au claim)
#   AWX_VAR_MAP       table `variable de survey -> variable d'environnement` (JSON).
#                     Explicite, comme VAR_MAP pour terraform : on ne DEVINE jamais
#                     le nom au lancement (sshPublicKey → ssh_public_key ? SSH_… ?).
#   AWX_ETAT_VAR      la variable d'état, pour les RESSOURCES (vide pour une action)
#   AWX_TIMEOUT       borne du suivi, en secondes — dite, jamais infinie
#   ETAT              posé par le verbe : present (apply) | absent (destroy)
#   token             le jeton AWX, monté par credsSecret (clé `token`)
#
# ⚠️ AWX refuse les extra_vars hors survey quand `ask_variables_on_launch` est faux :
# la variable de traçabilité n'est donc jointe QUE si le template l'accepte. Constaté,
# pas supposé.
set -euo pipefail

: "${AWX_URL:?AWX_URL requis}"
: "${AWX_JOB_TEMPLATE:?AWX_JOB_TEMPLATE requis}"
JETON="${AWX_TOKEN:-${token:-}}"
[ -n "$JETON" ] || { echo "ECHEC : aucun jeton AWX monté (credsSecret, clé 'token')" >&2; exit 1; }
API="${AWX_URL%/}/api/v2"
WEB="${AWX_WEB:-}"
TIMEOUT="${AWX_TIMEOUT:-1800}"
ETAT="${ETAT:-}"

aw() { curl -sS -H "Authorization: Bearer $JETON" -H 'Content-Type: application/json' "$@"; }

# ── Le job template, résolu par son NOM déclaré ───────────────────────────────
# Un 403 ici n'est pas un mystère : le compte de lancement ne voit que les templates
# dont le droit d'exécution lui a été accordé en git (13-jeton-lancement.yaml).
JT=$(aw -G --data-urlencode "name=$AWX_JOB_TEMPLATE" "$API/job_templates/" \
     | jq -r '.results[0].id // empty')
if [ -z "$JT" ]; then
  echo "ECHEC : job template « $AWX_JOB_TEMPLATE » introuvable ou hors de portée du jeton." >&2
  echo "        Les templates lançables sont déclarés dans JT_LANCABLES" >&2
  echo "        (platform-gitops/bootstrap/manifests/awx/13-jeton-lancement.yaml)." >&2
  exit 1
fi

DETAIL=$(aw "$API/job_templates/$JT/")
ASK_VARS=$(printf '%s' "$DETAIL" | jq -r '.ask_variables_on_launch')

# ── Les variables du survey, depuis les SPEC_* ────────────────────────────────
VARS=$(jq -nc '{}')
if [ -n "${AWX_VAR_MAP:-}" ]; then
  while IFS=$'\t' read -r sv env; do
    [ -n "$sv" ] || continue
    val="$(printenv "$env" || true)"
    # Un champ optionnel non rempli n'est pas envoyé : AWX appliquerait le défaut du
    # survey, ce qui est exactement ce que le demandeur a voulu en le laissant vide.
    [ -n "$val" ] || continue
    VARS=$(printf '%s' "$VARS" | jq -c --arg k "$sv" --arg v "$val" '. + {($k): $v}')
  done < <(printf '%s' "$AWX_VAR_MAP" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
fi
if [ -n "$AWX_ETAT_VAR" ]; then
  [ -n "$ETAT" ] || { echo "ECHEC : variable d'etat declaree mais ETAT non pose par le verbe" >&2; exit 1; }
  VARS=$(printf '%s' "$VARS" | jq -c --arg k "$AWX_ETAT_VAR" --arg v "$ETAT" '. + {($k): $v}')
fi
# Traçabilité : qui a demandé quoi. Le journal AWX porte déjà l'identité
# `portail-lancement` ; ceci y ajoute LA DEMANDE.
if [ "$ASK_VARS" = true ] && [ -n "${NOM_DEMANDE:-}" ]; then
  VARS=$(printf '%s' "$VARS" | jq -c --arg v "$NOM_DEMANDE" '. + {portail_demande: $v}')
fi

echo "lancement de « $AWX_JOB_TEMPLATE » (id $JT)${ETAT:+ · etat=$ETAT} · $(printf '%s' "$VARS" | jq -r 'keys | join(", ")')"

REP=$(curl -sS -o /tmp/launch.json -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $JETON" -H 'Content-Type: application/json' \
      -d "$(jq -nc --argjson v "$VARS" '{extra_vars: $v}')" "$API/job_templates/$JT/launch/")
JOB=$(jq -r '.id // empty' /tmp/launch.json 2>/dev/null || true)
if [ "$REP" != 201 ] || [ -z "$JOB" ]; then
  echo "ECHEC : AWX a refuse le lancement (HTTP $REP)" >&2
  # Le message d'AWX est SOUVENT actionnable (variable manquante, valeur hors choix) :
  # on le rend tel quel plutôt que de le résumer.
  jq -r '.' /tmp/launch.json 2>/dev/null | head -20 >&2 || true
  exit 1
fi
LIEN="${WEB:+$WEB/#/jobs/playbook/$JOB}"
echo "job AWX $JOB lance${LIEN:+ — $LIEN}"

# ── Le suivi, BORNÉ ───────────────────────────────────────────────────────────
# Le pod vit pendant le job : c'est un pod par LANCEMENT, pas par tour d'horloge —
# le contraire exact du modèle de coût qui a condamné le moteur précédent.
DEBUT=$(date +%s)
while :; do
  ST=$(aw "$API/jobs/$JOB/" | jq -r '.status // "inconnu"')
  case "$ST" in
    successful|failed|error|canceled) break ;;
  esac
  if [ $(( $(date +%s) - DEBUT )) -ge "$TIMEOUT" ]; then
    echo "ECHEC : le job AWX $JOB n'a pas fini en ${TIMEOUT}s (statut: $ST)" >&2
    echo "        Il CONTINUE côté AWX${LIEN:+ — $LIEN} : la demande echoue, le job non." >&2
    exit 1
  fi
  sleep 5
done

{
  echo "job=$JOB"
  echo "resultat=$ST"
  [ -n "$LIEN" ] && echo "journal=$LIEN"
  echo "jobTemplate=$AWX_JOB_TEMPLATE"
  [ -n "$ETAT" ] && echo "etat=$ETAT"
} >> "${SORTIES:-/dev/null}"

if [ "$ST" != successful ]; then
  echo "ECHEC : job AWX $JOB terminé en « $ST »${LIEN:+ — $LIEN}" >&2
  exit 1
fi
echo "job AWX $JOB : successful"
