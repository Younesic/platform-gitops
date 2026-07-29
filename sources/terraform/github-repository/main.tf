# LE PRODUIT : un dépôt git prêt à l'emploi.
#
# « Prêt à l'emploi » veut dire quelque chose de précis ici : le dépôt naît avec un
# commit initial, ses branches de travail, et sa branche principale protégée. Un dépôt
# vide livré à une équipe n'est pas un produit, c'est un ticket de plus.

resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = var.visibility

  # FIXÉ, pas exposé. Sans commit initial il n'y a aucune branche : ni branche
  # supplémentaire, ni protection possible. Voir variables.tf, § « ce qui n'est pas
  # dans le contrat ».
  auto_init = true

  # Ce que « supprimer la demande » fait vraiment. Par défaut on ARCHIVE : le code
  # survit en lecture seule. Détruire du code sur une suppression de ticket est le
  # genre d'irréversible qu'on ne met pas en défaut.
  archive_on_destroy = var.archive_on_destroy
}

# ── La branche principale ────────────────────────────────────────────────────────
# `auto_init` crée la branche par défaut du COMPTE, c'est-à-dire `main` (réglage
# GitHub depuis 2020). On ne fabrique donc une branche que si la demande en veut une
# autre — et le `count` porte sur une VARIABLE, connue au plan, jamais sur un attribut
# calculé (sinon terraform refuse de planifier).
resource "github_branch" "principale" {
  count = var.default_branch != "main" ? 1 : 0

  repository = github_repository.this.name
  branch     = var.default_branch
}

resource "github_branch_default" "principale" {
  count = var.default_branch != "main" ? 1 : 0

  repository = github_repository.this.name
  branch     = github_branch.principale[0].branch
}

# ── Les branches de travail ──────────────────────────────────────────────────────
# `toset` déduplique et rend la clé stable : réordonner la liste dans le formulaire ne
# doit provoquer AUCUN changement au plan. Une liste indexée par position ferait
# apparaître des destructions/créations fantômes au moindre réarrangement.
resource "github_branch" "travail" {
  for_each = toset([for b in var.branches : b if b != var.default_branch])

  repository    = github_repository.this.name
  branch        = each.value
  source_branch = var.default_branch

  depends_on = [github_branch_default.principale]
}

# ── La protection ────────────────────────────────────────────────────────────────
# Plus de poussée directe sur la principale, et une revue avant fusion. C'est le seul
# endroit du module qui relève de la gouvernance plutôt que de la plomberie.
#
# ⚠️ Sur un dépôt PRIVÉ, GitHub réserve la protection de branche aux plans payants
# (Pro/Team). Sur un compte gratuit avec `visibility = private`, l'apply échouera ici
# avec un message explicite de GitHub — c'est une limite de la plateforme d'en face,
# pas du module.
resource "github_branch_protection" "principale" {
  count = var.protect_default_branch ? 1 : 0

  repository_id = github_repository.this.node_id
  pattern       = var.default_branch

  # 🔑 LA PROTECTION S'APPLIQUE AUSSI AUX ADMINISTRATEURS. Non négociable, donc
  # pas exposé au contrat.
  #
  # PROUVÉ SUR LE PRODUIT LUI-MÊME : sans cette ligne, GitHub laisse un propriétaire
  # d'organisation écrire directement sur la branche « protégée » — mesuré, l'écriture
  # a réussi. Le portail aurait affiché « branche protégée » pendant que la personne
  # la plus capable de contourner n'était pas concernée : c'est un CONTRÔLE DÉCORATIF,
  # et un contrôle décoratif est pire qu'un contrôle absent, parce qu'il ferme la
  # question en comité.
  #
  # En faire une option reviendrait à offrir le bouton qui recrée le problème.
  enforce_admins = true

  required_pull_request_reviews {
    required_approving_review_count = 1
    # Une nouvelle poussée périme les approbations déjà données : sinon « approuvé »
    # ne veut plus rien dire dès le commit suivant. Même principe que le portier iTop.
    dismiss_stale_reviews = true
  }

  depends_on = [github_branch_default.principale]
}
