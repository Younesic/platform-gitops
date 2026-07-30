# ── ADOPTION : lier un dépôt qui EXISTE déjà ─────────────────────────────────────
#
# Quand `import_id` est renseigné, ce bloc dit à OpenTofu : « la ressource
# github_repository.this n'est pas à créer, elle EXISTE — la voici ». Au plan, le
# dépôt réel est lu et comparé à la déclaration (« will be imported » + l'écart) ;
# l'état n'est matérialisé qu'au premier APPLY — donc jamais tant que la demande
# reste en Observé (planOnly).
#
# Le `for_each` conditionnel est la forme idiomatique d'un import OPTIONNEL :
# liste vide = pas d'adoption, le module crée comme avant. (OpenTofu ≥ 1.7 ;
# le runner est en 1.12.)
#
# Une fois la ressource dans l'état (après le premier apply), ce bloc devient un
# no-op : il peut rester, il ne ré-importe pas.
import {
  for_each = toset(var.import_id == "" ? [] : [var.import_id])
  to       = github_repository.this
  id       = each.value
}
