# Module `harbor-project` — pour le moteur terraform NATIF

Un projet Harbor + son robot d'écriture + (optionnel) le mapping du groupe OIDC de la
squad en project-admin.

## Ce que c'est exactement

Un **port fidèle** du HCL qui vit *inline* dans
`sources/crossplane/harbor-project/composition.yaml`. Mêmes ressources, mêmes options,
mêmes sorties, aucune variable en plus.

**Pourquoi fidèle et pas « amélioré »** : l'objectif TN8 compare les deux moteurs sur le
**même produit**. Une variable de plus d'un côté fausserait la comparaison.

## Les deux différences avec la version crossplane, et pourquoi

| | crossplane (`provider-terraform`) | natif (`tofu-controller`) |
|---|---|---|
| **backend d'état** | déclaré dans le `ClusterProviderConfig` | **aucun** — le contrôleur gère l'état lui-même |
| **identifiants** | fichier injecté par le `ClusterProviderConfig` | **variables d'environnement du runner** |

Dans les deux cas, **le module ignore à quel Harbor il parle**. C'est ce qui le rend
réutilisable, et c'est une propriété à préserver.

## Les identifiants ne sont PAS des variables

Une variable terraform atterrit dans l'**état** et dans le **plan**. Un mot de passe passé
en variable serait donc lisible par qui lit le secret d'état — `sensitive` masque
l'affichage, **pas le stockage**.

La plateforme les injecte donc par l'environnement du pod runner
(`spec.runnerPodTemplate.spec.envFrom`), que le provider harbor lit tout seul :

```
HARBOR_URL · HARBOR_USERNAME · HARBOR_PASSWORD
```

## Le contrat

`variables.tf` **est** l'API exposée aux demandeurs. C'est de lui que TN5 dérivera la CRD
de la promesse :

| ce qu'on écrit dans le module | ce que ça produit dans le formulaire |
|---|---|
| pas de `default` | champ **requis** |
| `validation` avec `can(regex(...))` | le motif est appliqué |
| `validation` avec `contains([...])` | une **liste de choix** |
| `description` | le texte sous le champ |

| variable | type | défaut | |
|---|---|---|---|
| `project` | string | — | **requis**, motif `^[a-z][a-z0-9-]*$`, ≤ 255 |
| `group` | string | `""` | vide = pas de mapping de groupe |
| `storage_quota` | number | `-1` | -1 = illimité |
| `public` | bool | `false` | |

## Sorties

`project_name` · `robot_full_name` · `robot_secret` (sensible)

⚠️ Le secret du robot est **en clair dans l'état**, quel que soit le moteur. D'où le
chiffrement de l'état, non optionnel (TN7).
