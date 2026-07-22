#!/usr/bin/env bash
# logo-data-url.sh — génère la valeur `logo-url` (data: URI) pour la curation
# d'une promesse à partir d'un fichier image local.
#
# Pourquoi : Harbor est un registre OCI (pas un hébergeur de fichiers) ; le
# portail n'autorise que les hôtes allowlistés (CSP img-src + kratixMarketplace
# .logo.allowedHosts) MAIS admet nativement `data:image/…` → un logo encodé en
# base64 voyage dans l'annotation de la promesse, zéro hébergement, zéro config.
#
# Usage :
#   ./tools/logo-data-url.sh chemin/vers/logo.png
#   → imprime la data: URI (et la copie dans le presse-papiers si pbcopy/xclip)
#   → à coller telle quelle dans le champ `logo-url` de l'étape Curation.
set -euo pipefail

if [[ $# -ne 1 || ! -f "${1:-}" ]]; then
  echo "usage: $0 <fichier-image>  (png, jpg, svg, webp, gif)" >&2
  exit 1
fi
img="$1"

# MIME : `file` si dispo (fiable), sinon déduit de l'extension.
if command -v file >/dev/null 2>&1; then
  mime=$(file -b --mime-type "$img")
else
  case "${img##*.}" in
    png) mime=image/png ;;
    jpg|jpeg) mime=image/jpeg ;;
    svg) mime=image/svg+xml ;;
    webp) mime=image/webp ;;
    gif) mime=image/gif ;;
    *) echo "extension inconnue — précise un png/jpg/svg/webp/gif" >&2; exit 1 ;;
  esac
fi
# `file` rend image/svg pour certains SVG ; le navigateur exige svg+xml.
[[ "$mime" == "image/svg" ]] && mime=image/svg+xml
if [[ "$mime" != image/* ]]; then
  echo "ce fichier n'est pas une image ($mime)" >&2
  exit 1
fi

# base64 SANS retours à la ligne (portable macOS/Linux).
b64=$(base64 < "$img" | tr -d '\n')
uri="data:${mime};base64,${b64}"

# Garde-fou taille : la valeur vit dans une annotation k8s (256 Ko max toutes
# annotations confondues) et transite dans le claim/la fiche — rester léger.
len=${#uri}
if (( len > 65536 )); then
  echo "⛔ ${len} caractères (> 64 Ko) : trop lourd pour une annotation." >&2
  echo "   Réduis l'image (64-128 px suffisent pour une carte marketplace) :" >&2
  echo "   sips -Z 128 \"$img\" --out logo-128.png   # macOS" >&2
  exit 1
elif (( len > 30000 )); then
  echo "⚠️  ${len} caractères (> 30 Ko) : ça passe, mais un logo 64-128 px serait plus léger." >&2
fi

printf '%s\n' "$uri"
if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$uri" | pbcopy
  echo "✅ copié dans le presse-papiers (${len} caractères, ${mime})" >&2
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$uri" | xclip -selection clipboard
  echo "✅ copié dans le presse-papiers (${len} caractères, ${mime})" >&2
else
  echo "✅ généré (${len} caractères, ${mime}) — copie la ligne ci-dessus" >&2
fi
