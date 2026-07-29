# CE QUE LE DEMANDEUR REÇOIT.
#
# Ces sorties partent dans un Secret (`writeOutputsToSecret`) ET sont étiquetées sur la
# fiche du catalogue (TN7) : la `description` devient le libellé affiché. Un demandeur
# qui vient de commander un dépôt veut son adresse pour cloner — pas un identifiant
# technique à recopier.
#
# ⚠️ AUCUNE sortie n'est marquée `sensitive` ici, et c'est exact : une adresse de dépôt
# n'est pas un secret. C'est le contraste avec harbor-project, dont le `robot_secret`
# EST sensible — et où la sensibilité déclarée par le module est ce qui l'exclut du
# sélecteur de sorties (TN5). Ne marquez `sensitive` que ce qui l'est réellement :
# tout marquer sensible revient à ne rien marquer.

output "repo_url" {
  description = "Adresse du dépôt"
  value       = github_repository.this.html_url
}

output "clone_ssh" {
  description = "Commande de clonage (SSH)"
  value       = github_repository.this.ssh_clone_url
}

output "clone_https" {
  description = "Commande de clonage (HTTPS)"
  value       = github_repository.this.http_clone_url
}

output "full_name" {
  description = "Chemin complet du dépôt"
  value       = github_repository.this.full_name
}

output "default_branch" {
  description = "Branche principale"
  value       = var.default_branch
}
