# `github-repository` — un dépôt git prêt à l'emploi

Module Terraform destiné au **moteur terraform natif** (tofu-controller, jeu TN1→TN8).
Une demande = un dépôt GitHub créé avec son commit initial, ses branches de travail et
sa branche principale protégée.

C'est le premier produit **indus** écrit directement en Terraform, sans passer par
Crossplane. L'ancienne plateforme rendait le même produit par `provider-github`
d'Upbound — lui-même engendré automatiquement à partir de ce provider Terraform.
On enlève donc une couche, pas une capacité.

## Le contrat

Huit champs. Un seul est obligatoire.

| Champ | Type | Défaut | Rôle |
|---|---|---|---|
| `name` | texte | — **requis** | Nom du dépôt |
| `organization` | texte | *(vide)* | Où le créer ; vide = le compte de la plateforme |
| `description` | texte | *(vide)* | Une phrase, affichée sur GitHub et au catalogue |
| `visibility` | `private` \| `public` | `private` | Qui le voit |
| `default_branch` | texte | `main` | Branche principale |
| `branches` | liste | *(vide)* | Branches de travail créées au départ |
| `protect_default_branch` | oui/non | `oui` | Revue exigée, plus de poussée directe |
| `archive_on_destroy` | oui/non | `oui` | À la suppression : archiver plutôt que détruire |

Le contrat de la CRD s'en **dérive tout seul** (`hcl-to-crd.py`) : requis, listes de
choix, motifs, longueurs et libellés viennent des blocs `variable`. Rien n'est écrit
deux fois.

**Ce qui n'y est pas** est documenté dans `variables.tf` — `auto_init` (fixé, l'exposer
casserait le reste), les droits d'équipe (ils vivent dans le modèle d'identité), le
contenu initial (c'est un autre produit).

## Ce que le demandeur reçoit

Adresse du dépôt · clonage SSH · clonage HTTPS · chemin complet · branche principale.
Aucune n'est sensible — contrairement à `harbor-project` dont le `robot_secret` l'est.
Ne marquez `sensitive` que ce qui l'est : tout marquer revient à ne rien marquer.

## ⚠️ Identité — le point à trancher AVANT de brancher le produit

Le module lit `GITHUB_TOKEN` et `GITHUB_OWNER` dans l'environnement du runner
(`runnerPodTemplate.spec.envFrom`), jamais en variable — une variable atterrit dans
l'état et dans le plan.

**Créer un dépôt demande plus que ce que la plateforme détient aujourd'hui.**

| Identité | Peut créer un dépôt ? |
|---|---|
| GitHub App `attijari-portal`, jeton d'installation, sur un **compte personnel** | **Non.** GitHub réserve `POST /user/repos` aux jetons d'utilisateur |
| La même App sur une **organisation**, permission `Administration: write` | **Oui** |
| Un jeton personnel de portée `repo` | Oui — mais c'est un jeton durable, ce qu'on a retiré le 2026-07-28 |

L'App actuelle a `contents`, `metadata`, `pull_requests`, `statuses` — **pas
`administration`** — et `Younesic` est un compte utilisateur, donc sans organisation.

**Chemin recommandé : créer une organisation GitHub** (gratuit), y installer l'App avec
`Administration: write`. Ça donne au champ `organization` du contrat un sens réel, ça
préserve la doctrine « aucun jeton durable », et ça ouvre au passage les équipes GitHub
pour les droits d'accès. La création de l'organisation et l'octroi de la permission sont
des gestes utilisateur.

L'ancienne plateforme, elle, utilisait un **jeton personnel en dur**
(`project-as-code/providers/github-secret.yaml`) — c'est la réponse à « comment
faisait-on avant », et c'est aussi ce qu'on ne refait pas.

## Essayer le module à la main

```bash
cd platform-gitops/sources/terraform/github-repository
terraform init -backend=false
terraform validate

# avec une identité capable de créer un dépôt :
export GITHUB_TOKEN=…        # jamais dans un fichier, jamais dans l'historique
export GITHUB_OWNER=…
terraform plan -var name=essai-plateforme
```

Le `plan` seul ne crée rien : c'est la façon de vérifier le contrat sans toucher à
GitHub.

## Limites, dites franchement

- **Protection de branche sur un dépôt privé** : réservée aux plans payants (Pro/Team).
  Sur un compte gratuit avec `visibility = private`, l'apply échoue à cette étape avec
  un message explicite de GitHub. Limite de la plateforme d'en face, pas du module.
- **`default_branch` autre que `main`** : le module crée la branche puis la désigne par
  défaut ; `main` continue d'exister à côté. C'est le comportement attendu, pas un
  oubli.
- **Renommer un dépôt** se fait en place côté GitHub, mais changer `name` dans une
  demande **recrée** le dépôt (nouvelle ressource). À traiter comme une suppression
  suivie d'une création — avec `archive_on_destroy`, l'ancien est archivé, pas perdu.
