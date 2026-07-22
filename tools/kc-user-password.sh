#!/usr/bin/env bash
# kc-user-password.sh — récupère le mot de passe INITIAL d'un user Keycloak
# provisionné par la promesse `user` (brique keycloak-user).
#
# La Composition écrit les outputs Terraform (user_id, username, password) dans
# le connection secret `kc-user-<claim>-creds` (ns default). Ce script le lit et
# COPIE le mot de passe dans le presse-papiers SANS l'afficher (pas de
# shoulder-surfing, rien dans le scrollback) — `--show` pour l'imprimer quand
# il n'y a pas de presse-papiers (session SSH).
#
# Qui l'exécute : aujourd'hui un cluster-admin (le ns default est verrouillé) ;
# cible = un membre de la squad identity via le RBAC par-claim (option (a),
# resourceNames exact) — la commande restera LA MÊME.
#
# Usage :
#   ./tools/kc-user-password.sh clouduser          # copie le mdp, affiche le reste
#   ./tools/kc-user-password.sh clouduser --show   # imprime le mdp (pas de pbcopy)
#
# ⚠️ Le mot de passe est TEMPORAIRE (changement forcé au 1er login Keycloak).
#    Transmets-le par un canal sûr, jamais par mail/chat en clair.
set -euo pipefail

NS=default
claim="${1:-}"
show="${2:-}"

if [[ -z "$claim" ]]; then
  echo "usage: $0 <nom-du-claim> [--show]   (ex. $0 clouduser)" >&2
  exit 1
fi
secret="kc-user-${claim}-creds"

if ! kubectl -n "$NS" get secret "$secret" >/dev/null 2>&1; then
  echo "⛔ secret ${NS}/${secret} introuvable." >&2
  echo "   Le claim a-t-il convergé ? Vérifie :" >&2
  echo "     kubectl -n ${NS} get users.platform.example.io ${claim}" >&2
  echo "     kubectl -n ${NS} get xkeycloakusers ${claim}   # SYNCED/READY" >&2
  echo "     kubectl -n ${NS} get workspaces.tf.m.upbound.io" >&2
  exit 1
fi

get_key() {
  kubectl -n "$NS" get secret "$secret" -o jsonpath="{.data.$1}" 2>/dev/null | base64 -d
}

username=$(get_key username || true)
user_id=$(get_key user_id || true)
password=$(get_key password || true)

if [[ -z "$password" ]]; then
  echo "⛔ clé 'password' absente du secret — clés disponibles :" >&2
  kubectl -n "$NS" get secret "$secret" -o jsonpath='{.data}' \
    | python3 -c "import json,sys; print('   ' + ', '.join(json.load(sys.stdin).keys()))" >&2
  exit 1
fi

echo "user Keycloak : ${username:-?}  (id: ${user_id:-?})"
if [[ "$show" == "--show" ]]; then
  printf 'mot de passe initial : %s\n' "$password"
elif command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$password" | pbcopy
  echo "✅ mot de passe copié dans le presse-papiers (non affiché)"
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$password" | xclip -selection clipboard
  echo "✅ mot de passe copié dans le presse-papiers (non affiché)"
else
  echo "(pas de presse-papiers — relance avec --show pour l'imprimer)"
fi
echo "⚠️  TEMPORAIRE : changement forcé au 1er login — transmets par canal sûr."
