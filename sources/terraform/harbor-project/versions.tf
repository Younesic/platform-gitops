terraform {
  # OpenTofu 1.12.1 dans le runner (TN1). On n'exige pas plus haut que nécessaire :
  # un module qui exige une version que le moteur n'a pas échoue à l'init, pas au plan.
  required_version = ">= 1.3.0"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.0"
    }
  }

  # ⚠️ AUCUN bloc `backend` ici, VOLONTAIREMENT.
  # tofu-controller gère l'état lui-même (un secret `tfstate-<workspace>-<nom>` par
  # ressource Terraform). Déclarer un backend entrerait en conflit avec lui.
  # C'est l'écart le plus visible avec la voie crossplane, où le backend est injecté
  # par le ClusterProviderConfig.
}

# Les identifiants NE SONT PAS des variables de ce module — et c'est délibéré.
#
# POURQUOI. Une variable terraform atterrit dans l'ÉTAT et dans le PLAN. Un mot de passe
# passé en variable serait donc lisible par quiconque lit le secret d'état, même marqué
# `sensitive` (sensitive masque l'AFFICHAGE, pas le stockage).
#
# La plateforme les injecte donc par l'ENVIRONNEMENT du pod runner
# (`spec.runnerPodTemplate.spec.envFrom`), que le provider harbor lit tout seul :
#   HARBOR_URL · HARBOR_USERNAME · HARBOR_PASSWORD
#
# C'est l'exact équivalent du ClusterProviderConfig de la voie crossplane : le module
# ne sait pas à quel Harbor il parle, et c'est très bien ainsi — il reste réutilisable.
provider "harbor" {
  # Le registre est joint en interne, en clair : pas de certificat à vérifier.
  insecure = true
}
