#!/usr/bin/env bash
# annonce-github — ACTION (contrat déclaré, PROMISE-STANDARD §9quater) : ouvre une
# issue d'ANNONCE sur un dépôt de l'organisation, avec l'identité de la plateforme.
#
# Contrat du runner : SPEC_* (les champs de contract.schema.json), NOM_DEMANDE,
# GITHUB_TOKEN dans l'environnement, $SORTIES pour publier. Exit ≠ 0 = échec VISIBLE.
set -euo pipefail

: "${SPEC_REPO:?champ repo requis}"
: "${SPEC_TITRE:?champ titre requis}"
: "${GITHUB_TOKEN:?identité plateforme absente (montage /kratix/secrets/github)}"

corps="${SPEC_CORPS:-}"
corps="${corps}

---
Annonce ouverte par la plateforme (demande \`${NOM_DEMANDE:-inconnue}\`, moteur script
— une exécution qui se termine : supprimer la demande ne fermera pas cette issue)."

code=$(jq -n --arg t "$SPEC_TITRE" --arg b "$corps" '{title: $t, body: $b}' | \
  curl -sS -o /tmp/reponse.json -w '%{http_code}' \
       -H "Authorization: Bearer ${GITHUB_TOKEN}" \
       -H 'Accept: application/vnd.github+json' \
       -d @- "https://api.github.com/repos/${SPEC_REPO}/issues")

if [ "$code" != "201" ]; then
  echo "ECHEC : GitHub a répondu ${code} pour ${SPEC_REPO} —" >&2
  jq -r '.message // "réponse illisible"' /tmp/reponse.json >&2 || true
  echo "(dépôt inexistant, ou hors de la portée de l'App de la plateforme)" >&2
  exit 1
fi

url=$(jq -r '.html_url' /tmp/reponse.json)
numero=$(jq -r '.number' /tmp/reponse.json)
{
  echo "resultat=issue ouverte"
  echo "reference=${url}"
  echo "numero=${numero}"
} >> "$SORTIES"
echo "issue #${numero} ouverte sur ${SPEC_REPO}"
