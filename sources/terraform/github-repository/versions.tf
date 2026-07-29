terraform {
  # OpenTofu 1.12.1 dans le runner (TN1). On n'exige pas plus haut que nécessaire :
  # un module qui exige une version que le moteur n'a pas échoue à l'init, pas au plan.
  required_version = ">= 1.3.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # ⚠️ AUCUN bloc `backend` ici, VOLONTAIREMENT.
  # tofu-controller gère l'état lui-même (un secret `tfstate-<workspace>-<nom>` par
  # ressource Terraform). Déclarer un backend entrerait en conflit avec lui.
}

# Les identifiants NE SONT PAS des variables de ce module — même règle que harbor-project.
#
# POURQUOI. Une variable terraform atterrit dans l'ÉTAT et dans le PLAN. Un jeton passé
# en variable serait donc lisible par quiconque lit le secret d'état, même marqué
# `sensitive` (sensitive masque l'AFFICHAGE, pas le stockage).
#
# La plateforme l'injecte donc par l'ENVIRONNEMENT du pod runner
# (`spec.runnerPodTemplate.spec.envFrom`), que le provider github lit tout seul :
#   GITHUB_TOKEN · GITHUB_OWNER
#
# ⚠️ CE QUE LE JETON DOIT POUVOIR FAIRE, dit franchement : créer un dépôt.
# Un jeton d'installation d'App GitHub ne le peut PAS sur un compte personnel
# (GitHub réserve `POST /user/repos` aux jetons d'utilisateur) ; sur une ORGANISATION,
# il le peut avec la permission `Administration: write`. Voir le README, §Identité.
provider "github" {
  # Vide ⇒ on retombe sur GITHUB_OWNER (l'environnement du runner décide).
  # Renseigné ⇒ la demande désigne explicitement où le dépôt est créé.
  owner = var.organization != "" ? var.organization : null
}
