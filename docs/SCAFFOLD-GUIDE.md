<!-- CANONIQUE depuis 2026-07-18 (BR14) — ex-emplacement : new-cluster/native/scaffold/README.md (stub de redirection). Le CODE des plugins reste dans new-cluster/native/scaffold/ (embarqué dans l'image factory). -->
# Guide — créer une promesse conforme (avec le CLI officiel Kratix)

> **Règle : on ne construit AUCUN renderer.** On prend la variante `kratix init <X>-promise` qui colle à
> la source ; elle **génère la CRD ET câble un renderer partagé** maintenu par Syntasso.
> Exemple fil rouge : **`Workspace`** (namespace + quota + RBAC) → **`helm-promise`**.

## ⚡ Raccourci : les plugins `kratix new-helm-promise` / `new-crossplane-promise`
Toutes les étapes 2→6 ci-dessous en **une commande** (plugins kubectl-style, découverts par
`kratix plugin list` ; ils n'inventent rien : ils **enchaînent les commandes officielles**,
+ le convertisseur pour helm). L'aval commun (Backstage ×2, placement, résumé, --deploy)
vit dans `scaffold/plugin_lib.py` — seuls l'amont source + l'étape contrat diffèrent :
```bash
# source = chart Helm pinné (le contrat = values.schema.json, cf. §4)
kratix new-helm-promise database \
  --chart-url oci://harbor.212-47-226-56.nip.io/platform/database \
  --chart-version 0.1.0 --kind Database [--plural …] [--deploy]

# source = XRD + Composition(s) dans un repo git à une REF PINNÉE (le contrat = la XRD, cf. §7)
kratix new-crossplane-promise sandbox \
  --repo-url git@github.com:Younesic/platform-gitops.git --ref <tag|SHA> \
  --path sources/crossplane/sandbox --kind Sandbox --plural sandboxes [--deploy]

# source = recette compound.yaml (composer d'AUTRES promesses, cf. §8 — ou le COMPOSER du portail)
kratix new-compound-promise team-space \
  --repo-url git@github.com:Younesic/platform-gitops.git --ref <tag|SHA> \
  --path sources/compound/team-space --kind TeamSpace --plural teamspaces [--deploy]

# source = manifestes d'un OPÉRATEUR k8s existant, repo git à ref PINNÉE (le contrat = la CRD désignée, cf. §9)
kratix new-operator-promise rabbit \
  --repo-url git@github.com:Younesic/platform-gitops.git --ref v0.6.0 \
  --path sources/operator/rabbitmq --kind Rabbit --plural rabbits \
  [--api-schema-from rabbitmqclusters.rabbitmq.com] [--omit override] [--src DIR] [--max-deps-kb 800] [--deploy]
```
Install : `ln -sf $(pwd)/new-cluster/native/scaffold/kratix-new-helm-promise /opt/homebrew/bin/kratix-new_helm_promise`
(idem pour `kratix-new-crossplane-promise` ; le nom à underscores donne la commande à tirets,
convention kubectl — poser AUSSI le symlink à tirets, c'est lui que la factory appelle). Défauts
plateforme (image backstage, groupe, selector, repo GitOps) : `scaffold/defaults.env`.
**Cycle de vie des branches `promise/<nom>` (politique — BR13)** : la branche de revue
vit TANT QUE le PromiseRequest vit (la factory la re-force-pushe à chaque re-run —
idempotente, alignée sur main quand le généré est identique) ; **jamais de suppression
d'une branche à claim VIVANT** (elle serait re-poussée au tick suivant) ; une branche
devient ORPHELINE quand son claim est retiré (le pipeline delete ne touche pas les
branches — design factory, OP6) → **la suppression est un geste HUMAIN de ménage**
(`git push origin --delete promise/<nom>`). Invariant vérifiable :
`git branch -r | grep promise/` == la liste des PromiseRequests vivants.

**Équivalences prouvées** : workspace régénérée = structurellement identique à la prod (re-vérifié
après l'extraction de la lib) ; sandbox en mode clone = identique au mode `--src` local.
⚠️ Garder le CLI local aligné sur la version de l'image factory (v0.17.0 mini — `--functions`).
> Commandes vérifiées via le source du CLI + `--help`.

## 0. Choisir la variante (elle câble le renderer — tu n'écris rien)
| Source | Commande | Renderer câblé |
|---|---|---|
| **Chart Helm** (défaut, y compris manifestes bruts emballés en chart) | `helm-promise` | `helm-resource-configure` |
| **Crossplane (XRD+Composition)** — voir §7 | `crossplane-promise` | `from-api-to-crossplane-claim` |
| Operator existant (a sa CRD) | `operator-promise` | `from-api-to-operator` |
| Terraform / Pulumi | `tf-module-promise` / `pulumi-component-promise` | stages dédiés |
| **Bespoke** (rare) | `init promise` + `add container` (image maison) | — (tu l'écris) |

**Workspace = des manifestes → un petit chart Helm → `helm-promise`.** (Pas de XRD, pas de bash maison.)

---

## 1. Écrire le chart Helm (côté équipe source)
```
workspace-chart/
├── Chart.yaml
├── values.yaml     # team, environment, tier + la table des quotas par tier
└── templates/
    ├── namespace.yaml
    ├── quota.yaml       # le mapping tier→quota vit ICI (lookup Helm sur .Values.tier)
    ├── limitrange.yaml
    └── rbac.yaml
```

## 2. Pousser le chart dans Harbor — versionné = le pin de gouvernance
```bash
helm package workspace-chart                 # → workspace-0.1.0.tgz
helm push workspace-0.1.0.tgz oci://harbor.212-47-226-56.nip.io/platform
```

## 3. Générer la promesse (CRD + renderer câblés, automatiquement)
```bash
kratix init helm-promise workspace \
  --chart-url oci://harbor.212-47-226-56.nip.io/platform/workspace \
  --chart-version 0.1.0 \
  --group platform.example.io --kind Workspace --dir workspace
cd workspace
```
→ `promise.yaml` avec **la CRD** (déduite des `values`) **+ le workflow câblé sur `helm-resource-configure`**.
Au runtime, ce renderer **pull le chart depuis Harbor** (`CHART_URL`/`CHART_VERSION` en ENV) et rend les
manifestes. **Tu n'écris aucun renderer.**

## 4. 🧾 Le contrat de l'API — `values.schema.json` dans le chart (ZÉRO hand-edit)
`helm-promise` déduit des **types de base** (pas d'`enum`). Le contrat riche (enums, `required`,
`pattern`, `default`, descriptions) s'écrit **UNE fois, dans le chart** — `values.schema.json`
(mécanisme Helm natif) — puis se dérive mécaniquement dans le CRD :

```bash
python3 new-cluster/native/scaffold/schema-to-crd.py <chart-dir|chart.tgz> promise.yaml
```

Pourquoi c'est le bon endroit : pour une helm-promise le renderer passe le `spec` du claim
**tel quel** comme values → **l'API EST le contrat de values**. Un seul fichier donne :
1. le **CRD** (validation à l'admission du claim) — dérivé, plus jamais édité à la main ;
2. la **validation Helm au rendu** (`helm template` refuse des values hors schéma) — gratuite ;
3. le **formulaire du portail** (le Template poussé est généré depuis ce même CRD).

Conventions : schéma « plat » (pas de `$ref`), `type` à chaque niveau, `x-kratix-internal: true`
pour exclure un knob interne de l'API. Le convertisseur retire aussi le `default: {}` piégeux
posé par le générateur (rejeté par k8s dès qu'il y a `required`). Tests : `python3
new-cluster/native/scaffold/test_schema_to_crd.py`. **Équivalence stricte prouvée** sur Workspace
(CRD régénéré identique au CRD précédemment hand-edité).

## 5. Le portail — fiche du provisionné ET Template (le même conteneur partagé, ×2)
```bash
# fiche (Component kratix-resource + annotations SKE + dependsOn fiche promesse + entités Resource + status) sur chaque claim :
kratix add container resource/configure/instance-configure \
  --image harbor.212-47-226-56.nip.io/platform/backstage-component@sha256:4cf04400735cb6662b6574cc70add6d2a3765cda6e95f6809355315cd849a30c \
  --name backstage
# Template scaffolder + FICHE PROMESSE (Component kratix-promise, 2e type SKE) poussés au portail :
kratix add container promise/configure/promise-configure \
  --image harbor.212-47-226-56.nip.io/platform/backstage-component@sha256:4cf04400735cb6662b6574cc70add6d2a3765cda6e95f6809355315cd849a30c \
  --name backstage
```
*(Le Template est GÉNÉRÉ depuis `spec.api` et poussé — plus d'ingestor, plus de label portal.
Supprimer les stubs `workflows/**/backstage/` créés par `add container` : l'image partagée ne se rebuilde pas.)*

## 6. Placement + déploiement
```bash
kratix update destination-selector environment=platform
# copier promise.yaml dans platform-gitops/bootstrap/manifests/kratix-promises/, commit, push → ArgoCD applique
# (ou via la factory : un claim PromiseRequest fait tout ça et ouvre la branche de revue)
```
> **Granularité de routage (RT0)** : une Destination = un env(×cell), jamais plus fin ;
> provider/produit/consumer = labels/annotations, jamais des segments de chemin. **RT1 fait
> (2026-07-16)** : le produit déclare son scope dans SON claim — `PromiseRequest.spec.placement`
> (UNE paire `label=valeur`) ; **omis = `environment=platform`** (control-plane/« shared ») ;
> **produit applicatif = `fleet=apps`** (un selector Promise sur `environment` serait
> inoverridable par claim — la clé est désormais libre pour le routage par claim, RT2 au
> déclencheur 2ᵉ Destination). Décision + plan : PROMISE-STANDARD §3 et
> `native/DESTINATION-ROUTING-ANALYSIS.md`.

## 7. Variante crossplane — la XRD EST le contrat (zéro étape schéma)
Remplace les §1-4 helm ; les §5-6 (Backstage ×2, placement, GitOps) sont identiques — le
plugin `kratix new-crossplane-promise` fait tout (cf. ⚡). Côté équipe source :
```
sources/crossplane/<nom>/     # dans un repo git — pin par TAG ou SHA (jamais une branche)
├── xrd.yaml                  # 1 CompositeResourceDefinition (le contrat de l'API)
└── composition.yaml          # ≥1 Composition (+ Function si besoin) — layout libre, multi-doc OK
```
`kratix init crossplane-promise` **copie le schéma de la XRD tel quel** dans l'API de la
promesse et met XRD + Compositions en `dependencies` (installées sur la Destination).
Référence vivante : `platform-gitops/sources/crossplane/sandbox/` (prouvée E2E).

**Contraintes du renderer officiel (vérifiées dans le source kratix-cli v0.17.0)** :
- l'objet rendu est créé dans le **namespace `default`** de la Destination (codé en dur) ;
- XRD v1 avec `claimNames` → rendu du claim ; **XRD v2 sans claims → rendu du XR direct** :
  écrire des XRD **v2 `scope: Namespaced`** (une XR cluster-scoped recevrait un namespace
  parasite, et une XR namespacée ne compose QUE des ressources namespacées — pas de MR
  cluster-scoped) ;
- un champ **requis** top-level sans `default` dans la XRD → warning du CLI (mettre un default) ;
- pièges Composition : avec la **function** patch-and-transform, les transforms string exigent
  `string.type: Format` (≠ patches v1) ; un ConfigMap composé a besoin de
  `readinessChecks: [{type: None}]` (pas de conditions).
- le selector par défaut `crossplane: enabled` posé par init est retiré par le plugin
  (`update destination-selector crossplane-`) — sinon la promesse ne se place jamais.

## 8. Variante compound — composer d'autres promesses (la RECETTE est le contrat)
Une compound émet **1 claim enfant par entrée `children`** (renderer partagé
`compound-renderer`, recette embarquée en ENV — aucune image par compound) ; les
`children[].{promise,version}` deviennent `requiredPromises` (gate d'installation).
**DEUX chemins à parité** :
1. **Le COMPOSER du portail** (formulaire promise-factory, type `compound`) : la recette
   naît du formulaire (`spec.recipe` inline du PromiseRequest) — enfants choisis via
   **EntityPicker** sur les fiches `kratix-promise` ; `version`/`apiVersion`/`kind`
   VIDES = résolus depuis la promesse installée et PINNÉS à la génération.
   **L'API parent se DÉRIVE des enfants** (union de leurs champs avec les contraintes
   réelles — enums/patterns/defaults/objets ; homonymes identiques fusionnés et routés
   vers chaque enfant ; mappings `${spec.<champ>}` auto). Curation : `fix` (figer une
   valeur → champ retiré du parent), `hide` (masquer un optionnel — un requis se fige),
   `recipe.api` = ajouts/overrides explicites, `spec` = override avancé d'un mapping.
   **La branche de revue montre l'API dérivée complète = le point de curation.**
   Gouvernance ×2 (PR du claim, puis branche de revue qui embarque la recette).
2. **Recette dans git** (équipes, recettes réutilisables/taguées) :
   `sources/compound/<nom>/compound.yaml` à ref pinnée → `kratix new-compound-promise
   <nom> --repo-url … --ref <tag|SHA> --path … --kind <Kind> [--plural …]`.
   Référence vivante : `platform-gitops/sources/compound/team-space/`.

**Topologies** (toutes exprimables depuis le formulaire) :
| Topologie | Comment |
|---|---|
| T1 bundle | lignes `children` simples |
| T2 conditionnel | `when: [{field, exists\|equals}, …]` (déclaratif, pas d'eval) + `whenMode: all\|any` (ET/OU) |
| T3 DAG / data-passing | `needs: [noms]` + `exports: {clé: .status.chemin}` → l'enfant attend ses requis, lit leur status, consomme `${children.<nom>.<clé>}` |
| T4 récursif | une compound installée apparaît dans le picker → compound de compounds |
| T5 multi-destination | porté par le placement de chaque promesse enfant |

**Architecture T3 — pipelines ÉTAGÉS (impératif Kratix)** : un run qui écrit
`workflow-control retryAfter` ne committe PAS ses outputs → jamais d'émission+attente
dans le MÊME pipeline. Le plugin génère donc `instance-configure` (émet la profondeur 0,
ne retry jamais) + **un pipeline `gated-<n>` PAR PROFONDEUR du DAG** (tout-ou-retry :
émet son niveau si tous les requis sont `ConfigureWorkflowCompleted`, sinon retryAfter 60 s).
C'est la généralisation du split create/wait de Syntasso (app-stack). NB : le dernier
retryAfter pose `kratix.io/workflow-suspended=true` sur le claim et une suspension
**survit à l'update de la promesse** → purge par `kratix.io/manual-reconciliation=true`.

**Gotchas vérifiés** :
- `requiredPromises` = **égalité STRICTE** de version sur notre Kratix (« vide = any »
  n'existe pas ici) → toujours pinner (le composer résout+pinne automatiquement).
- Templating : valeur EXACTEMENT `${chemin}` = valeur NATIVE du parent (types
  préservés) ; sinon interpolation string. Coercion des littéraux RESTRICTIVE
  (`true|false|entiers` — jamais « yes »→bool).
- Dans une recette GIT, écrire les specs en **style block** (`team: ${spec.team}`) —
  le style flow `{team: ${…}}` est du YAML invalide.
- Suppression : sync-wave = profondeur DAG posée par le renderer → au prune du parent,
  les dépendants partent AVANT leurs dépendances ; R-TPL-7 protège l'intérieur de
  chaque enfant. Supprimer les CLAIMS avant les PROMESSES (gotcha deadlock).
- `exports` : chemins pointés simples sous `.status` (pas d'index de tableau).
  Depuis le renderer ≥ 0.3.x (**uplift V4-0**), une valeur ABSENTE du claim est
  résolue en suivant `status.provisionedResources` jusqu'à la ressource RÉELLE
  (XR crossplane, objet core helm, CR operator) — le mur « Completed ≠
  provisionné » est fermé ; le picker LABELLISÉ (status-schema) propose les
  champs. Pour du câblage intra-crossplane, la **référence par nom déterministe**
  (ex. `kc-group-<groupe>`, cf. sources/crossplane/keycloak-*) reste le pattern
  le plus robuste : la valeur ne voyage jamais, la résolution attend toute seule.
- Champ OPTIONNEL absent du parent : un token pur `${spec.x}` non résolu **OMET
  la clé** du claim enfant (renderer ≥ 0.3.2 — jamais `null`, rejeté par les
  schémas structuraux ; contrat « omis = pas d'attribut »). Une interpolation
  string (`team-${spec.x}`) rend `''` pour le token manquant (inchangé).
- Les champs **ARRAY traversent la dérivation** (`users: [a, b]` remonte tel quel
  jusqu'au formulaire parent, token pur `${spec.users}` = liste native — prouvé
  E2E teamaccess/team-space). Limite du dialecte composer (KV scalaires) :
  ENVELOPPER un scalaire dans une liste (`users: ["${spec.user}"]`) = recette
  git seulement.

## 9. Variante operator — la CRD désignée EST le contrat (prouvé E2E sur `rabbit`)

Wrapper un **opérateur k8s existant** (release officielle YAML) en promesse : les manifestes
ENTIERS deviennent `spec.dependencies` inline (opérateur installé **1×/Destination**), l'API
de la promesse = **la CRD désignée copiée telle quelle** (spec+status, version **STORAGE**),
le renderer officiel `from-api-to-operator` rend **1 CR par claim** (nom = claim,
`namespace: default` FORCÉ, labels/annotations du claim propagés, spec passthrough).

**Flux** : vendoriser la release (`sources/operator/<nom>/` sur platform-gitops, taguer) →
`kratix new-operator-promise` (cf. ⚡) — ou depuis le portail : `PromiseRequest`
`{type: operator, source: {url, version, path, apiSchemaFrom, omit[]}}` (wizard Studio =
picker repo/tag/dossier + Select « CRD contrat » alimenté par l'aperçu derive).

- **Désignation de la CRD contrat** : `--api-schema-from <plural.group>` ; **omise si la
  source n'a qu'UNE CRD** ; plusieurs CRDs sans désignation = **erreur guidée listant**
  (le wizard en fait un Select). Les manifestes `kind: List` sont dépliés à la découverte.
- **Curation `--omit <champ>`** (répétable) = `kratix update api --property <champ>-`
  officiel. **BR5 : chemins POINTÉS admis** (`--omit override.statefulSet` = retrait NESTED,
  reste du parent intact + `required` orphelin nettoyé par le plugin — le CLI le laisse, vérifié). ⚠️ Cas d'école vécu : les défauts PROFONDS de `override` (RabbitMQ) rendent le
  formulaire insoumettable (requireds imbriqués matérialisés par rjsf) → l'omission est LA
  correction ; le champ jamais posé = défauts de l'opérande.
- **Garde de taille** : deps inline vs etcd → `OPERATOR_DEPS_MAX_KB=800` (defaults.env) /
  `--max-deps-kb` ; refus guidé au-delà (grafana 771 Ko + 13 CRDs écarté ; rabbit 342 Ko OK,
  appliqué en ServerSideApply par l'app kratix-promises). **BR6 (décision instrumentée)** :
  limite FERME par défaut — refus enrichi de 2 voies (vendoriser le RENDU, ex. minio
  `kubectl kustomize` 255 Ko admissible ; deps-par-workflow PARTAGÉ au déclencheur) ;
  mesures + design dans PROMISE-STANDARD §9 ; amplification deps→Promise ≈ ×2,2 mesurée.
- **Renderer épinglé par DIGEST sur le miroir Harbor** (`OPERATOR_RENDERER_IMAGE`) — le tag
  ghcr documenté `v0.2.2` était FANTÔME (ImagePullBackOff silencieux, un Job en IPBO ne fail
  jamais) ; politique digest-pinning appliquée au renderer comme au reste.
- **Exports** : `add_status_schema` (plugin_lib) annote la promesse depuis le status de la
  CRD → picker labellisé (V4-2) + uplift V4-0 au runtime (la valeur est lue sur le CR réel).
- **`--src DIR`** = mode dev local ; équivalence clone≡src testée (diff vide).
- **Limites** (détail : PROMISE-STANDARD §9) : un opérateur = UNE promesse · CR dans
  `default` (pas d'homonymes cross-ns) · fiche/graphe = le CR seul (le live peut montrer les
  enfants SI l'opérateur propage les labels — RabbitMQ le fait) · famille du groupe tiers à
  ajouter à customresources-sync+RBAC (1 ligne chacun) · ownership : label
  `component-of-owner` au claim ou compound wrapper — **jamais** `update api --property
  team:string` (admission STRICTE du CR : unknown field rejeté, prouvé au dry-run serveur).
- **Suppression = gouvernance** (retirer une CRD tue TOUS les CRs du groupe) : instances
  d'abord (l'opérateur reste), la promesse ensuite (deps prunées) ; jamais l'inverse
  (deadlock PromiseRevision — remède : révision de secours + nudge, cf. PROMISE-STANDARD §9).

---

## 10. Variante ansible — le rôle EST le contrat (parc SANS API Kubernetes)

Pour tout ce que Kubernetes ne sait pas décrire : VM, middleware, appliances,
Windows, legacy. **AAP exécute, Kubernetes réconcilie.**

```bash
kratix new-ansible-promise sauvegarde \
    --repo-url git@github.com:Younesic/platform-gitops.git \
    --ref v0.14.0 --path sources/ansible-roles/legacy-service \
    --job-template legacy-service \
    --inventory 'Parc legacy' \
    --awx-token-secret awx-token-cloud \
    --kind Sauvegarde [--plural sauvegardes] [--deploy]
```

Ce que le plugin fait : clone à la ref **pinnée** → dérive la CRD depuis
`meta/argument_specs.yml` → assemble les **quatre** fichiers du produit (CRD,
watches, Deployment sur le runtime partagé, RBAC) → **délègue à
`kratix new-operator-promise --src`**. Le chemin d'exécution est donc, à la ligne
près, celui du moteur operator.

### Ce qu'il faut écrire, côté équipe source

```yaml
# roles/<mon-role>/meta/argument_specs.yml — LE contrat, écrit UNE fois
argument_specs:
  main:
    short_description: Ce que fait le rôle
    options:
      service_name:
        type: str
        required: true
        description: Nom technique du service sur la machine cible.
      marker_state:
        type: str
        choices: [present, absent]
        default: present
        x-kratix-internal: true     # piloté par le runtime, pas par le demandeur
```

`str/int/float/bool/list/dict` → types OpenAPI ; `choices` → `enum` ; `required`,
`default` et `description` sont repris tels quels. Une option marquée
`x-kratix-internal: true` **n'est pas exposée** au demandeur.

Aperçu avant de publier :
```bash
python3 new-cluster/native/scaffold/argspec-to-crd.py <role> \
    --group temoin.ansible.example.io --kind LegacyService -o crd.yaml
```

### Par le portail

`spec.type: ansible` avec `source` (url/version/path) **et** un bloc `automation` :
`jobTemplate` (le seul autorisé), `inventory` **ou** `allowedLimits`, et
`awxTokenSecret` (le jeton du fournisseur). Les quatre règles CEL de la
méta-promesse refusent à l'admission un claim incomplet — **dont celui qui ne
déclare pas sa cible**.

### Les pièges rencontrés (payés une fois, pas deux)

| Piège | Ce qu'il faut faire |
|---|---|
| Les noms du rôle ≠ les variables du **sondage** AWX | AWX exige TOUTES les variables requises d'un sondage, **même celles qui ont un défaut** (400 « value missing »). Le contrat dérivé et le sondage doivent être le même contrat, nom pour nom. Un écart rend le produit inutilisable **et indestructible**. |
| `role:` dans un `watches.yaml` | ansible-operator v1.42 le lit comme un **fichier** (« is a directory »). Passer par `playbook:` — les deux enveloppes partagées sont là pour ça. |
| Référence arrière d'un regex en scalaire replié | `'_\1'` et **non** `'_\\1'` : la seconde forme produit le texte littéral, et le job part avec un nom de variable cassé. Un test le verrouille. |
| Corps de requête écrit champ par champ en Jinja | Il produit des **chaînes** : l'API refuse (422 « must be of type integer »). Le corps doit être **une seule** expression Jinja pour rendre un vrai dictionnaire typé. |
| Jeton rangé avec un saut de ligne final | En-tête HTTP invalide chez **tous** les consommateurs. `jq -j`, jamais `jq -r`. |
| L'image d'operator-sdk | Elle n'embarque **aucune collection** : ni `kubernetes.core`, ni `operator_sdk.util`. N'utiliser que `ansible.builtin` + le jeton de compte de service. |

### Supprimer

Les **demandes d'abord**, on attend qu'elles soient parties, **la promesse
ensuite** — la règle d'or du projet (cf. PROMISE-STANDARD §9bis). Retirer une
promesse ansible ne touche ni le runtime partagé ni AWX.

## 11. Variante terraform natif — le module EST le contrat

```bash
kratix new-terraform-promise harbor-tf \
  --repo-url https://github.com/Younesic/platform-gitops \
  --ref v0.17.0 --path sources/terraform/harbor-project \
  --kind HarborTf --plural harbortfs \
  --approval auto --interval 1h \
  --creds-secret harbor-identifiants \
  --provider indus --public [--deploy]
```

Le plugin **assemble**, il ne réinvente rien :

1. clone à la **ref pinnée** (tag ou SHA — jamais une branche) ;
2. le contrat se **dérive** des blocs `variable` (`hcl-to-crd`) ;
3. la **source du module devient une dépendance** de la promesse — appliquée une fois par
   Destination, pas clonée par demande ;
4. le rendu écrit une ressource `Terraform` nommée d'après la demande ;
5. l'aval commun : conteneur Backstage ×2, placement, famille d'API déclarée, sorties
   étiquetées.

**Deux options sont OBLIGATOIRES à penser, parce qu'elles ne se devinent pas** :

- `--approval auto|manuelle` — **surveillée OU approuvée, pas les deux.** Avec une
  approbation nommée, la dérive est détectée mais **jamais corrigée**.
- `--interval` — **chaque tour fait naître un pod.** À 2 min : 720 pods/jour/demande.

**Gotchas du moteur** (les vrais, ceux qui coûtent du temps) :

- `kubectl` refuse le **singulier** `terraform` — employer `terraforms` ou `tf`. Le message
  (« you must specify only one resource ») ne désigne pas la cause.
- un **rejeu local** de la fabrique **sans** `KRATIX_WORKFLOW_ACTION=configure` et
  `KRATIX_WORKFLOW_TYPE=resource` sort en **code 0 sans rien dire**.
- le service `schema-derive` écoute sur **8080**, pas 80.
- **HCL : un bloc sur une seule ligne n'accepte qu'un argument.** Deux arguments →
  « Invalid single-argument block definition ». Gotcha payé deux fois.
- après plusieurs échecs, le contrôleur reste en **attente exponentielle** : corriger la
  cause ne suffit pas, il faut **réveiller**
  (`reconcile.fluxcd.io/requestedAt`, ou `kratix.io/manual-reconciliation` côté demande).

## Vérifier
```bash
kubectl get promises                          # Available
kubectl get workspace -A                      # la demande est Reconciled
kubectl get ns -l platform.kratix.io/team     # le namespace est Active
```

## Gouvernance (le point clé)
- Le chart est **versionné dans Harbor** ; la promesse **épingle `--chart-version`**.
- L'équipe source change → **nouvelle version** (`0.2.0`) → **bump** de `--chart-version` **par une PR revue**.
- **Rollback** = garder l'ancienne version. Immuabilité stricte = **tags immuables Harbor** (ou digest).
- **Jamais** de source mutable non épinglée (sinon casse silencieuse).

## Le cas « bespoke » (rare — à éviter)
Si **aucune** variante ne colle (logique vraiment sur-mesure) : `kratix init promise` + `kratix add container
--image <ton-image>` + tu écris le `pipeline.sh`. **Inconvénient : 1 image custom par promesse à maintenir →
ça ne scale pas.** Réserve-le au vrai 20 %.

---

## Récap
- **Officiel (zéro renderer maison)** : chart Helm → Harbor → `init helm-promise` → CRD + renderer câblés.
- **Contrat unique (zéro hand-edit)** : `values.schema.json` dans le chart → `schema-to-crd.py` dérive le CRD ; Helm valide les values au rendu avec le même fichier.
- **Crossplane** : XRD v2 namespacée + Composition(s) dans un repo git pinné → `new-crossplane-promise` (la XRD est le contrat, zéro conversion).
- **Compound** : composer des promesses installées — depuis le COMPOSER du portail (recette inline, EntityPicker, versions auto-pinnées) ou une recette git pinnée → `new-compound-promise` (T1 bundle, T2 when, T3 needs/exports, cf. §8).
- **Operator** : wrapper un opérateur existant — release vendorisée dans un repo git pinné → `new-operator-promise` (la CRD désignée est le contrat, deps inline 1×/Destination, curation `--omit`, cf. §9) ; suppression = gouvernance (instances d'abord, promesse ensuite).
- **Ne pas faire** : renderer générique maison, générateur schéma→CRD (sauf grande échelle), kro/kustomize pour un namespace.
