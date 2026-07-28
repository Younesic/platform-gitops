# PORT FIDÈLE du HCL qui vit aujourd'hui *inline* dans la Composition crossplane
# (`sources/crossplane/harbor-project/composition.yaml`), extrait en vrai module.
#
# Rien n'a été ajouté ni retiré : mêmes trois ressources, mêmes options, même condition
# sur le mapping de groupe. C'est ce qui permet à TN8 de comparer les deux moteurs sur
# le MÊME produit, et non sur deux produits qui se ressemblent.

resource "harbor_project" "this" {
  name                   = var.project
  public                 = var.public
  vulnerability_scanning = true
  storage_quota          = var.storage_quota
}

# Le robot d'écriture : ce sont SES identifiants que la CI du fournisseur emploie
# pour publier. Il naît et meurt avec le projet.
resource "harbor_robot_account" "publisher" {
  name        = "publisher"
  description = "Robot write plateforme pour le projet ${var.project}"
  level       = "project"

  permissions {
    access {
      action   = "push"
      resource = "repository"
    }
    access {
      action   = "pull"
      resource = "repository"
    }
    kind      = "project"
    namespace = harbor_project.this.name
  }
}

# L'accès HUMAIN : le groupe OIDC de la squad devient project-admin.
# Vide = pas de mapping (le robot suffit à publier) — d'où le `count`.
resource "harbor_project_member_group" "admins" {
  count      = var.group == "" ? 0 : 1
  project_id = harbor_project.this.id
  group_name = var.group
  role       = "projectadmin"
  type       = "oidc"
}
