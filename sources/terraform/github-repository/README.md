# `github-repository` — un dépôt git prêt à l'emploi

Module Terraform destiné au **moteur terraform natif** (tofu-controller, jeu TN1→TN8).
Une demande = un dépôt GitHub créé avec son commit initial, ses branches de travail et
sa branche principale protégée.

C'est le premier produit **indus** écrit directement en Terraform, sans passer par
Crossplane. L'ancienne plateforme rendait le même produit par `provider-github`
d'Upbound — lui-même engendré automatiquement à partir de ce provider Terraform.
On enlève donc une couche, pas une capacité.

## Le contrat

Huit champs. Deux sont obligatoires : **quoi** et **où**.

| Champ | Type | Défaut | Rôle |
|---|---|---|---|
| `name` | texte | — **requis** | Nom du dépôt |
| `organization` | texte | — **requis** | Organisation qui l'héberge |
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

Le module lit **`GITHUB_TOKEN`** dans l'environnement du runner
(`runnerPodTemplate.spec.envFrom`), jamais en variable — une variable atterrit dans
l'état et dans le plan.

**Une seule variable d'environnement**, et c'est voulu : la plateforme fournit le
*droit d'agir*, la demande dit *où*. Pas de `GITHUB_OWNER` à câbler, donc pas de
cible décidée en silence côté plateforme.

### ⚠️ Il faut une organisation — ce n'est pas un confort, c'est la condition

Mesuré le 2026-07-29, deux fois, avec le droit réellement accordé sur l'installation :

| Appel | Jeton d'installation d'App |
|---|---|
| `POST /user/repos` (compte personnel) | **403** `Resource not accessible by integration` — **même avec `administration: write` accordé** |
| `POST /orgs/{org}/repos` | **passe** |

GitHub réserve la création de dépôt sur un compte personnel aux jetons d'*utilisateur*.
Un jeton d'App n'en est pas un, et aucune permission ne change ça.

**En place aujourd'hui** : App `attijari-portal` installée sur l'organisation
`YounesicCo` (installation `149916529`, portée *all*, `administration: write`). Le
CronJob `github-token-org` frappe le jeton toutes les 30 min dans
`default/github-app-token-org` — il expire en une heure, rien de durable ne circule.

L'ancienne plateforme, elle, utilisait un **jeton personnel en dur**
(`project-as-code/providers/github-secret.yaml`) — c'est la réponse à « comment
faisait-on avant », et c'est aussi ce qu'on ne refait pas.

### Pourquoi `organization` est requis plutôt que par défaut

Un défaut ferait décider à la plateforme où le code d'une équipe atterrit,
silencieusement — et une erreur de cible ne se voit pas passer. Le fournisseur qui n'a
qu'une organisation ne condamne pas son demandeur à la retaper : il **fige** le champ
en concevant la promesse (mode « Fixé » du Studio). Le module reste générique, la
promesse porte la convention.

## Essayer le module à la main

```bash
cd platform-gitops/sources/terraform/github-repository
terraform init -backend=false
terraform validate

# avec le jeton de la PLATEFORME — jamais un jeton personnel.
# Il n'est jamais affiché, et il expire dans l'heure.
export GITHUB_TOKEN=$(kubectl -n default get secret github-app-token-org \
                        -o jsonpath='{.data.token}' | base64 -d)

terraform plan -var name=essai -var organization=YounesicCo
```

Le `plan` seul ne crée rien : c'est la façon de vérifier le contrat sans toucher à
GitHub. Une sonde encore plus sûre, si l'on doute du droit avant même de planifier :
un `POST` de nom vide rend `422` quand l'authentification passe, `403` sinon — aucun
effet de bord dans les deux cas.

## Éprouvé en réel (2026-07-29, organisation `YounesicCo`)

Deux cycles complets contre le vrai GitHub, pas contre une doublure.

**Cycle 1 — avec un jeton personnel**, pour valider le module :

| Geste | Résultat mesuré |
|---|---|
| `plan` | 4 objets à créer, lisible |
| `apply` | dépôt **privé** + `main`/`develop`/`recette` + protection, **30 s** |
| écriture directe sur `main` (propriétaire) | **201 — passée** ⇒ défaut trouvé |
| correctif `enforce_admins` | plan = **une seule ligne**, en place |
| même écriture, après | **409 — « Changes must be made through a pull request »** |
| `destroy` (défaut) | dépôt **archivé**, `archived: true`, code conservé |

**Cycle 2 — avec le jeton de la PLATEFORME** (l'App, jamais un jeton personnel) :

| Geste | Résultat mesuré |
|---|---|
| `apply` | dépôt privé + `main`/`develop` + protection |
| écriture directe sur `main` **par la plateforme** | **409** — elle ne contourne pas la protection qu'elle pose |
| `destroy` avec `archive_on_destroy=false` | **suppression réelle** |
| état final | organisation à **0 dépôt**, zéro résidu |

## Limites, dites franchement

- **Protection de branche sur un dépôt privé** : réservée aux plans payants (Pro/Team).
  `YounesicCo` est en plan **team**, donc disponible. Sur un compte gratuit avec
  `visibility = private`, l'apply échoue à cette étape avec un message explicite de
  GitHub. Limite de la plateforme d'en face, pas du module.
- **Archiver demande moins de droits que détruire, mais pas pour tout le monde** :
  avec un jeton *personnel*, archiver relève de la portée `repo` et supprimer exige
  `delete_repo` en plus — le défaut sûr est donc aussi le moins privilégié. Avec un
  jeton d'*App*, `administration: write` couvre les deux (vérifié : la suppression
  réelle passe). Le défaut reste l'archivage : ce n'est plus une contrainte de droits,
  c'est un choix.
- **`default_branch` autre que `main`** : le module crée la branche puis la désigne par
  défaut ; `main` continue d'exister à côté. C'est le comportement attendu, pas un
  oubli.
- **Renommer un dépôt** se fait en place côté GitHub, mais changer `name` dans une
  demande **recrée** le dépôt (nouvelle ressource). À traiter comme une suppression
  suivie d'une création — avec `archive_on_destroy`, l'ancien est archivé, pas perdu.
