# LE CONTRAT DU PRODUIT.
#
# Ce fichier est la source de vérité de l'API exposée aux demandeurs : c'est de LUI que
# TN5 dérivera la CRD de la promesse (types, requis, contraintes, descriptions), comme
# `values.schema.json` pour helm et `meta/argument_specs.yml` pour ansible.
#
# Règle de dérivation, écrite ici pour que l'auteur du module sache ce qu'il pilote :
#   · pas de `default`            → le champ est REQUIS
#   · `validation` avec `contains([...])` → le champ devient une LISTE DE CHOIX
#   · `validation` avec `can(regex(...))` → le champ reçoit ce motif
#   · `description`               → le texte affiché sous le champ du formulaire

variable "project" {
  type        = string
  description = "Nom du projet Harbor (le registre du fournisseur, ex. team-paiement)."
  # Pas de défaut : c'est le seul champ obligatoire.

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project))
    error_message = "Le nom doit commencer par une lettre minuscule et ne contenir que des minuscules, des chiffres et des tirets."
  }

  validation {
    condition     = length(var.project) <= 255
    error_message = "Le nom ne peut pas dépasser 255 caractères."
  }
}

variable "group" {
  type        = string
  default     = ""
  description = "Groupe OIDC (ex. team-paiement) à qui accorder project-admin sur le projet. Vide = pas de mapping de groupe (le robot write suffit à publier)."
}

variable "storage_quota" {
  type        = number
  default     = -1
  description = "Quota de stockage du projet en Go (-1 = illimité)."

  validation {
    condition     = var.storage_quota == -1 || var.storage_quota > 0
    error_message = "Le quota doit valoir -1 (illimité) ou un nombre de Go strictement positif."
  }
}

variable "public" {
  type        = bool
  default     = false
  description = "Projet public (lecture anonyme des artefacts)."
}

# ⚠️ PAS de variable `role` ici, et c'est volontaire.
#
# La Composition crossplane fixe `projectadmin` en dur. Ce module en est un PORT FIDÈLE :
# TN8 compare le MÊME produit sur deux moteurs, et une variable en plus d'un côté
# fausserait la comparaison. TN5 aura son propre module de test, synthétique, pour
# éprouver la dérivation des listes de choix (`contains`) et des types profonds.
