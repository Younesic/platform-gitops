# LE CONTRAT DU PRODUIT.
#
# Ce fichier est la source de vérité de l'API exposée aux demandeurs : c'est de LUI que
# `hcl-to-crd.py` (TN5) dérive la CRD de la promesse — types, requis, contraintes,
# descriptions —, comme `values.schema.json` pour helm et `meta/argument_specs.yml`
# pour ansible.
#
# Règle de dérivation, rappelée ici pour que l'auteur du module sache ce qu'il pilote :
#   · pas de `default`                    → le champ est REQUIS
#   · `validation` avec `contains([...])` → le champ devient une LISTE DE CHOIX
#   · `validation` avec `can(regex(...))` → le champ reçoit ce motif
#   · `validation` avec `length(...) <= N`→ longueur maximale
#   · `description`                       → le texte affiché sous le champ du formulaire
#
# TAILLE DU CONTRAT — assumée. Huit champs, choisis pour couvrir tout ce qu'un dépôt
# demande vraiment au quotidien (où, comment il s'appelle, qui le voit, quelles
# branches, protège-t-on la principale, que se passe-t-il à la suppression) sans
# recopier les ~40 arguments du provider. Un contrat qu'on ne peut pas lire d'un coup
# d'œil ne se remplit pas.

variable "name" {
  type        = string
  description = "Nom du dépôt (ex. paiement-api). C'est le seul champ obligatoire."
  # Pas de défaut : c'est ce qui le rend requis.

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.name))
    error_message = "Le nom doit commencer par une lettre ou un chiffre, et ne contenir que des lettres, chiffres, points, tirets et tirets bas."
  }

  validation {
    condition     = length(var.name) <= 100
    error_message = "Le nom ne peut pas dépasser 100 caractères."
  }
}

variable "organization" {
  type        = string
  default     = ""
  description = "Organisation GitHub qui hébergera le dépôt. Vide = le compte configuré sur la plateforme."

  # ⚠️ Le « vide autorisé » est DANS le motif (`^$|`), pas dans une garde
  # `var.organization == "" || …` devant lui. Les deux écritures sont correctes côté
  # Terraform, mais celle-ci se dérive fidèlement par n'importe quelle version de
  # `hcl-to-crd` : elle ne dépend pas de la lecture des disjonctions.
  #
  # (La forme à garde est désormais gérée elle aussi — c'est le défaut trouvé sur ce
  # module même : le motif seul était recopié, et la CRD refusait le défaut vide du
  # champ, donc une demande vierge. Voir `contraintes()` dans hcl-to-crd.py.)
  validation {
    condition     = can(regex("^$|^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.organization))
    error_message = "Le nom d'organisation ne peut contenir que des lettres, chiffres et tirets."
  }
}

variable "description" {
  type        = string
  default     = ""
  description = "Une phrase décrivant le dépôt. Affichée sur GitHub et dans le catalogue."
}

variable "visibility" {
  type        = string
  default     = "private"
  description = "Qui peut voir le dépôt. Privé par défaut : on n'ouvre jamais par accident."

  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "La visibilité doit valoir private ou public."
  }
}

variable "default_branch" {
  type        = string
  default     = "main"
  description = "Branche principale du dépôt."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._/-]*$", var.default_branch))
    error_message = "Le nom de branche ne peut pas commencer par un caractère spécial."
  }
}

variable "branches" {
  type        = list(string)
  default     = []
  description = "Branches supplémentaires à créer au départ (ex. develop, recette). La branche principale n'est pas à répéter ici."
}

variable "protect_default_branch" {
  type        = bool
  default     = true
  description = "Protéger la branche principale : plus de poussée directe, une revue exigée avant fusion."
}

variable "archive_on_destroy" {
  type        = bool
  default     = true
  description = "À la suppression de la demande : archiver le dépôt (le code est conservé, en lecture seule) plutôt que le détruire."
}

# ⚠️ CE QUI N'EST PAS DANS LE CONTRAT, et pourquoi — les absences sont des décisions.
#
# · `auto_init` — FIXÉ à true dans main.tf, pas exposé. Un dépôt sans commit initial n'a
#   aucune branche : on ne peut ni en créer d'autres, ni protéger la principale. L'exposer
#   reviendrait à offrir un réglage qui casse silencieusement la moitié du produit.
#   (L'ancien contrat crossplane l'exposait avec `default: true` — même effet, un piège
#   en plus.)
#
# · les équipes / droits d'accès — ils vivent dans le modèle d'identité de la plateforme
#   (`team-<slug>`), pas dans un champ de formulaire recopié à la main. À brancher quand
#   une organisation existera, par le même chemin que les autres produits.
#
# · le contenu initial (fichiers, gabarits) — c'est un AUTRE produit. Un dépôt qui naît
#   avec un squelette imposé est un choix de gouvernance, pas une option de création.
