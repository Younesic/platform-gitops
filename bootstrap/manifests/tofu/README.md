# Exécuteur terraform natif — source-controller + tofu-controller

Objectif **TN1** du set `backstage-platform/Objectives/terraform-native/`.

## Ce que c'est, et ce que ce n'est pas

**Ce n'est PAS Flux.** On installe exactement deux contrôleurs :

| contrôleur | version | métier |
|---|---|---|
| `source-controller` | v1.9.3 | va chercher un dépôt / un artefact et le met en cache |
| `tofu-controller` | v0.16.4 | exécute OpenTofu et réconcilie la ressource `Terraform` |

Pas de `kustomize-controller`, pas de `helm-controller`, pas de
`notification-controller`. **ArgoCD reste le seul moteur GitOps du cluster** — rien ici ne
réconcilie git vers le cluster.

Le `source-controller` est là par **obligation** : le champ `sourceRef` de la ressource
`Terraform` est requis et n'accepte que ses types (`GitRepository`, `Bucket`,
`OCIRepository`). C'est une dépendance, au même titre que cert-manager pour Kratix.

Le namespace s'appelle `flux-system` parce que les manifestes officiels le codent en dur.
Le renommer obligerait à patcher l'amont à chaque montée de version, pour un gain nul.

## Images — toutes pinnées par empreinte

| image | empreinte |
|---|---|
| `ghcr.io/fluxcd/source-controller:v1.9.3` | `sha256:ff8f3c92…` |
| `ghcr.io/flux-iac/tofu-controller:v0.16.4` | `sha256:7f95e82a…` |
| `ghcr.io/flux-iac/tf-runner:v0.16.4` | `sha256:fc3af4d9…` |

⚠️ **L'image du runner est distincte de celle du contrôleur, et c'est elle qui compte** :
c'est elle qui embarque **OpenTofu 1.12.1** et qui exécute réellement le code
d'infrastructure. Elle se pin par la variable `RUNNER_POD_IMAGE`.

## Ce qui vient de l'amont, et ce qu'on a écrit

| fichier | origine |
|---|---|
| `10-source-controller-crds.yaml` | amont, **verbatim** |
| `11-source-controller-rbac.yaml` | **écrit par nous** — l'artefact de release ne contient aucun droit |
| `12-source-controller.yaml` | amont + 3 écarts signalés en ligne (namespace, compte de service, empreinte) |
| `20-tofu-controller-crds.yaml` | amont, **verbatim** |
| `21-tofu-controller-rbac.yaml` | amont, **verbatim** — ⚠️ voir ci-dessous |
| `22-tofu-controller.yaml` | amont + 2 pins par empreinte |

## ⚠️ Le point de sécurité à porter en comité

Le fichier RBAC livré par l'amont contient :

```yaml
kind: ClusterRoleBinding
metadata: { name: tf-cluster-reconciler }
roleRef:  { kind: ClusterRole, name: cluster-admin }
subjects: [ { kind: ServiceAccount, name: tf-controller, namespace: flux-system } ]
```

**Le compte de service du contrôleur est `cluster-admin` sur tout le cluster.** C'est le
choix de l'amont, et il a une logique : un module terraform peut employer le provider
kubernetes et créer n'importe quoi. Nous le **vendorisons tel quel** — le restreindre
casserait des cas d'usage légitimes et nous ferions diverger un composant que nous ne
maintenons pas.

Mais **ce n'est pas anodin dans une banque**, et ça doit être une décision consciente, pas
une découverte. À chiffrer et à trancher en **TN8**, avec au moins ces options :
restreindre le rôle aux groupes d'API réellement employés par les modules exposés ·
exiger un `ServiceAccount` dédié par produit (`spec.serviceAccountName` existe sur la
ressource `Terraform`) · ou assumer et documenter.

Par contraste, le RBAC du `source-controller` est **écrit par nous et nominatif** : il lit
des dépôts, il n'écrit rien dans le cluster.

## Contraintes d'application

- **`ServerSideApply=true` est obligatoire** : la CRD `terraforms.infra.contrib.fluxcd.io`
  pèse ~770 Ko. En application côté client, l'annotation `last-applied-configuration`
  doublerait la charge et approcherait la limite d'un objet etcd (1,5 Mo). Piège déjà
  rencontré avec la promesse operator (750 Ko).
- Le `Namespace` est déclaré ici en **sync-wave -1** (R-TPL-7 : il doit exister avant les
  comptes de service et les Role/RoleBinding qui vivent dedans).

## Montée de version

Re-télécharger les artefacts de release, re-résoudre les trois empreintes, reporter les
écarts signalés en ligne. Les fichiers `*-crds.yaml` et `21-*-rbac.yaml` se remplacent
**verbatim**.
