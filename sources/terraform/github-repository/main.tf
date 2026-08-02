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

  # ── ADOPTION : le plan d'un dépôt IMPORTÉ doit finir VIDE ──────────────────────
  # Trois familles d'attributs pollueraient le plan d'adoption sans rien dire d'utile :
  #   · `auto_init` — ne sert qu'à la CRÉATION ; sur un dépôt importé il est faux en
  #     état et vrai en config, un écart sans aucun effet réel ;
  #   · `has_issues/has_projects/has_wiki` — HORS CONTRAT : le module ne les gouverne
  #     pas, il ne doit donc JAMAIS les modifier (ni à l'adoption, ni après) ;
  #   · `ignore_vulnerability_alerts_during_read` — drapeau virtuel du provider.
  # ⚠️ `archive_on_destroy` n'est PAS ignoré, et c'est voulu : l'ignorer le laisserait
  # vide dans l'état d'un dépôt adopté, et une suppression DÉTRUIRAIT au lieu
  # d'archiver. Son enregistrement au premier apply est le seul « change » légitime
  # d'une adoption alignée — il est PROTECTEUR.
  lifecycle {
    ignore_changes = [
      auto_init,
      has_issues,
      has_projects,
      has_wiki,
      ignore_vulnerability_alerts_during_read,
    ]
  }
}

# ── La branche principale ────────────────────────────────────────────────────────
# `auto_init` crée la branche par défaut du COMPTE, c'est-à-dire `main` (réglage
# GitHub depuis 2020). On ne FABRIQUE donc une branche que si la demande en veut une
# autre — et le `count` porte sur une VARIABLE, connue au plan, jamais sur un attribut
# calculé (sinon terraform refuse de planifier).
resource "github_branch" "principale" {
  count = var.default_branch != "main" ? 1 : 0

  repository = github_repository.this.name
  branch     = var.default_branch
}

# ⚠️⚠️ CE `count` A ÉTÉ RETIRÉ, ET C'EST UN CORRECTIF DE FOND — CONSTATÉ EN PRODUCTION.
#
# Il valait `var.default_branch != "main" ? 1 : 0`, par le même raisonnement que la
# ressource ci-dessus : « GitHub crée `main` tout seul, inutile de le forcer ».
#
# Ce raisonnement est juste POUR UNE CRÉATION et FAUX POUR UNE ADOPTION. Un dépôt qui
# existe déjà peut avoir N'IMPORTE QUELLE branche par défaut. Avec le `count`, une
# demande déclarant `main` sur un dépôt dont la branche par défaut est `integration`
# ne produisait AUCUNE ressource — donc terraform ne gérait pas ce champ, et l'écart
# n'était JAMAIS corrigé, même en Géré.
#
# MESURÉ sur `socle-metier-2019` : branche par défaut basculée à la main sur
# `integration`, passage en Géré, apply réussi — `develop` créée, protection posée,
# description vidée — et `integration` TOUJOURS EN PLACE. Le champ était demandé au
# formulaire, enregistré dans le claim, et jamais appliqué : la plateforme affichait
# une valeur qu'elle ne tenait pas.
#
# La branche par défaut est donc GÉRÉE DANS TOUS LES CAS. Sur un dépôt neuf c'est un
# no-op (GitHub a déjà posé `main`) ; sur un dépôt adopté, c'est la seule chose qui
# ramène l'écart.
#
# ⚠️ On pointe `var.default_branch` et NON `github_branch.principale[0].branch` : cette
# dernière n'existe pas quand la branche déclarée est `main`. La dépendance d'ordre est
# portée par `depends_on`, qui tolère une ressource à `count = 0`.
#
# ⚠️ LIMITE DITE : si un dépôt adopté déclare une branche par défaut qui N'EXISTE PAS
# chez lui, l'apply échoue — GitHub refuse de pointer le défaut sur une branche absente.
# C'est un refus JUSTE et lisible au plan, pas un défaut à masquer.
resource "github_branch_default" "principale" {
  repository = github_repository.this.name
  branch     = var.default_branch

  depends_on = [github_branch.principale]
}

# Le retrait du `count` change l'ADRESSE de la ressource dans l'état. Aucune instance
# vivante n'est concernée (les trois déclarent `main`, donc `count` valait 0 et la
# ressource n'existait dans aucun état — vérifié avant d'écrire). Mais un dépôt ayant
# déclaré une autre branche AURAIT `…principale[0]` : sans ce bloc, la montée de version
# lui afficherait une DESTRUCTION au plan. Alarmant, et inutile.
moved {
  from = github_branch_default.principale[0]
  to   = github_branch_default.principale
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
