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

## Ce que « protégée » veut dire ici

Quand `protect_default_branch` vaut oui : une revue exigée avant fusion, les
approbations annulées à chaque nouvelle poussée, ni poussée forcée ni suppression —
**et la règle s'applique aussi aux administrateurs** (`enforce_admins`).

Ce dernier point n'est pas une option, et il a été payé cher : sans lui, GitHub laisse
un propriétaire d'organisation écrire **directement** sur la branche « protégée ».
Mesuré sur ce module même — l'écriture a réussi (HTTP 201) alors que le portail aurait
affiché « branche protégée ». C'est un **contrôle décoratif**, et un contrôle décoratif
est pire qu'un contrôle absent : il ferme la question en comité. Après correction, la
même tentative rend `409 — Changes must be made through a pull request`.

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

## Éprouvé en réel (2026-07-29, organisation `YounesicCo`)

Cycle complet joué contre le vrai GitHub, pas contre une doublure :

| Geste | Résultat mesuré |
|---|---|
| `plan` | 4 objets à créer, lisible |
| `apply` | dépôt **privé** + `main`/`develop`/`recette` + protection, **30 s** |
| écriture directe sur `main` (propriétaire) | **201 — passée** ⇒ défaut trouvé |
| correctif `enforce_admins` | plan = **une seule ligne**, en place |
| même écriture, après | **409 — « Changes must be made through a pull request »** |
| `destroy` (défaut) | dépôt **archivé**, `archived: true`, **code conservé** |

## Limites, dites franchement

- **Protection de branche sur un dépôt privé** : réservée aux plans payants (Pro/Team).
  `YounesicCo` est en plan **team**, donc disponible. Sur un compte gratuit avec
  `visibility = private`, l'apply échoue à cette étape avec un message explicite de
  GitHub. Limite de la plateforme d'en face, pas du module.
- **Archiver demande moins de droits que détruire** : l'archivage est une modification
  du dépôt (portée `repo`), la suppression exige `delete_repo`. Le défaut sûr est donc
  aussi celui qui réclame le moins — c'est heureux, mais ça veut dire qu'une plateforme
  qui voudrait vraiment détruire devrait demander un droit de plus, délibérément.
- **`default_branch` autre que `main`** : le module crée la branche puis la désigne par
  défaut ; `main` continue d'exister à côté. C'est le comportement attendu, pas un
  oubli.
- **Renommer un dépôt** se fait en place côté GitHub, mais changer `name` dans une
  demande **recrée** le dépôt (nouvelle ressource). À traiter comme une suppression
  suivie d'une création — avec `archive_on_destroy`, l'ancien est archivé, pas perdu.
