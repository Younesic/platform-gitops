# Projet Dependency-Track — pilote du moteur `api` (PROMISE-STANDARD §9quinquies).
#
# Ce module est ÉCRIT MAIN pour la porte OA2 : il est le point de comparaison de ce que
# le dériveur produira en OA4. Tout ce qu'il contient doit donc être DÉRIVABLE de
# `spec.json` (pinné à côté) + de la désignation écrite dans le README — rien d'autre.
#
# LA DÉSIGNATION — elle ne se devine pas (voir le README pour le détail mesuré) :
#   create → PUT    /api/v1/project           ⚠️ chez DT, PUT crée
#   read   → GET    /api/v1/project/{uuid}
#   update → PATCH  /api/v1/project/{uuid}    ⚠️ POST modifie, mais sur la COLLECTION :
#                                                dirigé vers l'item il rend 405 (mesuré)
#   delete → DELETE /api/v1/project/{uuid}

terraform {
  required_providers {
    restful = {
      source  = "magodo/restful"
      version = "~> 0.16"
    }
  }
}

# ── Les identifiants ne sont PAS des variables de ce module, et c'est délibéré ──
# La doctrine du dépôt (harbor-project, github-repository) : une variable terraform
# atterrit dans le plan lisible et voyage avec la demande. Le provider `restful` n'a
# aucun support de variables d'environnement (son `base_url` est requis en
# configuration — vérifié sur son schéma), donc on ne peut pas faire comme harbor.
# On passe donc par des FICHIERS montés dans le runner : `file()` est évalué à
# l'exécution, la valeur ne traverse ni le claim, ni l'état, ni le plan (le plan ne
# garde que l'EXPRESSION `file(...)`, jamais son résultat).
locals {
  dtrack_url = trimspace(file("/dtrack/DTRACK_URL"))
  dtrack_key = trimspace(file("/dtrack/DTRACK_API_KEY"))
}

provider "restful" {
  base_url = local.dtrack_url
  security = {
    apikey = [{
      name  = "X-Api-Key"
      in    = "header"
      value = local.dtrack_key
    }]
  }
}

variable "nom" {
  type        = string
  description = "Nom du projet dans Dependency-Track."
  validation {
    condition     = length(var.nom) > 0 && length(var.nom) <= 255
    error_message = "Le nom est requis et ne peut dépasser 255 caractères (contrainte de la spec)."
  }
}

variable "version_projet" {
  type        = string
  default     = ""
  description = "Version du projet — une même application peut en avoir plusieurs."
}

variable "classifier" {
  type        = string
  default     = "APPLICATION"
  description = "Nature du composant (énumération de la spec)."
  validation {
    condition = contains([
      "APPLICATION", "FRAMEWORK", "LIBRARY", "CONTAINER", "OPERATING_SYSTEM",
      "DEVICE", "FIRMWARE", "FILE", "PLATFORM", "DEVICE_DRIVER",
      "MACHINE_LEARNING_MODEL", "DATA"
    ], var.classifier)
    error_message = "Valeur hors de l'énumération déclarée par la spec."
  }
}

variable "description" {
  type        = string
  default     = ""
  description = "Description libre du projet."
}

# ── L'ADOPTION ─────────────────────────────────────────────────────────────────
# La LIAISON du moteur `api` est l'identifiant de l'objet dans l'API — ici l'uuid que
# l'opération `read` attend en chemin. Renseignée, la plateforme REPREND un projet
# existant au lieu d'en créer un ; l'uuid reste le même (c'est toute la question).
variable "import_id" {
  type        = string
  default     = ""
  description = "UUID d'un projet Dependency-Track EXISTANT à adopter. Vide = création."
  validation {
    condition     = var.import_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.import_id))
    error_message = "L'identifiant d'adoption doit être un UUID de 36 caractères."
  }
}

resource "restful_resource" "projet" {
  path          = "/api/v1/project"
  create_method = "PUT"
  read_path     = "/api/v1/project/$(body.uuid)"
  update_method = "PATCH"
  update_path   = "/api/v1/project/$(body.uuid)"

  # Les champs optionnels non renseignés ne sont pas ENVOYÉS : l'API applique alors
  # son propre défaut, ce qui est exactement ce que le demandeur a voulu en laissant
  # le champ vide (le geste du lanceur AWX, repris ici).
  body = merge(
    {
      name       = var.nom
      classifier = var.classifier
    },
    var.version_projet == "" ? {} : { version = var.version_projet },
    var.description == "" ? {} : { description = var.description },
  )
}

# Le bloc `import` conditionnel — le motif exact du module d'adoption de référence
# (github-repository). Absent d'identifiant, il ne s'instancie pas : un greenfield ne
# paie rien pour un chemin d'adoption qu'il n'emprunte pas.
# ⚠️ Chez `restful`, l'identifiant d'import est un JSON qui décrit AUSSI comment relire
# la ressource — le provider est générique, il ne peut pas le deviner.
import {
  for_each = toset(var.import_id == "" ? [] : [var.import_id])
  to       = restful_resource.projet
  id = jsonencode({
    id            = "/api/v1/project/${each.value}"
    path          = "/api/v1/project"
    create_method = "PUT"
    body = merge(
      {
        name       = var.nom
        classifier = var.classifier
      },
      var.version_projet == "" ? {} : { version = var.version_projet },
      var.description == "" ? {} : { description = var.description },
    )
  })
}

output "uuid" {
  value       = restful_resource.projet.output.uuid
  description = "UUID du projet dans Dependency-Track — la liaison d'adoption."
}

output "nom" {
  value       = var.nom
  description = "Nom du projet."
}
