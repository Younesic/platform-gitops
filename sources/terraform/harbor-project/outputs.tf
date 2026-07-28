# LES SORTIES DU PRODUIT.
#
# Ce sont elles qui, en TN3, remonteront dans le statut de la demande et alimenteront le
# sélecteur de sorties étiquetées du Studio — comme `outputs.schema.json` pour helm et le
# `status` de la XRD pour crossplane.
#
# Mêmes sorties que la Composition crossplane, à l'identique.

output "project_name" {
  value       = harbor_project.this.name
  description = "Nom du projet Harbor provisionné."
}

output "robot_full_name" {
  value       = harbor_robot_account.publisher.full_name
  description = "Nom complet du robot write (robot$<projet>+publisher)."
}

# ⚠️ `sensitive` masque l'AFFICHAGE, pas le STOCKAGE : cette valeur est en clair dans
# l'état. C'est vrai des deux moteurs, et c'est la raison pour laquelle le chiffrement
# de l'état n'est pas optionnel en banque (TN7).
output "robot_secret" {
  value       = harbor_robot_account.publisher.secret
  sensitive   = true
  description = "Secret du robot write. À consommer par la CI du fournisseur, jamais à afficher."
}
