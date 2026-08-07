# ⚙️ MODULE GÉNÉRÉ par le moteur `api` — ne pas éditer à la main.
#
# Source du contrat : la spec PINNÉE à côté (`spec.json`) — la plateforme ne la lit
# jamais à chaud. Source des verbes : la DÉSIGNATION, qui ne se devine pas :
#   create → PUT    /v1/project
#   read   → GET    /v1/project/{uuid}
#   update → PATCH  /v1/project/{uuid}
#   delete → DELETE /v1/project/{uuid}

terraform {
  required_providers {
    restful = {
      source  = "magodo/restful"
      version = "~> 0.16"
    }
  }
}

# Les identifiants arrivent par des FICHIERS montés dans le runner, jamais par des
# variables terraform : une variable voyagerait dans le plan lisible. `file()` est
# évalué à l'exécution — le plan ne garde que l'expression.
#
# ⚠️ LE SECRET DOIT PORTER CES CLÉS, exactement :
#     DTRACK_URL · DTRACK_API_KEY   (et API_USER pour l'authentification basic)
# Un nom qui ne correspond pas fait échouer le PLAN à chaque tour, avec un message
# de terraform qui parle d'un fichier absent — jamais du secret. Les noms se
# déclarent dans la demande (`api.credsKeys`) quand ils diffèrent de la convention.
locals {
  base_url    = trimspace(file("/api-creds/DTRACK_URL"))
  jeton       = trimspace(file("/api-creds/DTRACK_API_KEY"))
  utilisateur = fileexists("/api-creds/API_USER") ? trimspace(file("/api-creds/API_USER")) : ""
}

provider "restful" {
  base_url = local.base_url
  security = {
    apikey = [{
      name  = "X-Api-Key"
      in    = "header"
      value = local.jeton
    }]
  }
}

variable "classifier" {
  type = string
  default = ""
  validation {
    condition = var.classifier == "" || contains(["NONE", "APPLICATION", "FRAMEWORK", "LIBRARY", "CONTAINER", "OPERATING_SYSTEM", "DEVICE", "FIRMWARE", "FILE", "PLATFORM", "DEVICE_DRIVER", "MACHINE_LEARNING_MODEL", "DATA"], var.classifier)
    error_message = "Valeur hors de l'énumération déclarée par la spec."
  }
}

variable "description" {
  type = string
  default = ""
  validation {
    condition = var.description == "" || length(var.description) <= 255
    error_message = "La spec limite ce champ à 255 caractères."
  }
}

variable "name" {
  type = string
  default = ""
  validation {
    condition = var.name == "" || length(var.name) <= 255
    error_message = "La spec limite ce champ à 255 caractères."
  }
}

variable "version_valeur" {
  type = string
  # ⚠️ le champ du contrat s'appelle `version` : ce nom est RÉSERVÉ par terraform, la variable est donc suffixée.
  default = ""
}

# ── L'ADOPTION ─────────────────────────────────────────────────────────────────
# La LIAISON de ce moteur est l'identifiant de l'objet dans l'API — celui que
# l'opération `read` attend en chemin (« uuid »).
variable "import_id" {
  type = string
  default = ""
  description = "Identifiant d'un objet EXISTANT à reprendre au lieu d'en créer un. Vide = création."
}

resource "restful_resource" "objet" {
  path          = "/v1/project"
  create_method = "PUT"
  read_path     = "/v1/project/$(body.uuid)"
  update_method = "PATCH"
  update_path   = "/v1/project/$(body.uuid)"

  # Un champ optionnel non renseigné n'est PAS envoyé : l'API applique alors son
  # propre défaut, ce que le demandeur a voulu en laissant le champ vide.
  body = merge(
    {
    },
    var.classifier == "" ? {} : { classifier = var.classifier },
    var.description == "" ? {} : { description = var.description },
    var.name == "" ? {} : { name = var.name },
    var.version_valeur == "" ? {} : { version = var.version_valeur },
  )
}

# Bloc `import` conditionnel — le motif du module d'adoption de référence. Absent
# d'identifiant, il ne s'instancie pas : un greenfield ne paie rien pour un chemin
# qu'il n'emprunte pas.
import {
  for_each = toset(var.import_id == "" ? [] : [var.import_id])
  to       = restful_resource.objet
  id = jsonencode({
    id            = "/v1/project/${each.value}"
    path          = "/v1/project"
    create_method = "PUT"
    body = {

    }
  })
}

output "uuid" {
  value       = restful_resource.objet.output.uuid
  description = "Identifiant de l'objet dans l'API — la liaison d'adoption."
}
