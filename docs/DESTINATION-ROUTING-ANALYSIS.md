<!-- CANONIQUE depuis 2026-07-18 (BR14) — ex-emplacement : new-cluster/native/DESTINATION-ROUTING-ANALYSIS.md (stub de redirection) -->
# Routage des Destinations Kratix — analyse & verdict sur la hiérarchie de chemins `provider/produit/env/consumer`

> **Question posée** : l'ancien routage hiérarchique (chemins ergonomiques `provider/produit/env/consumer/…`, segment `shared` pour les produits non env-scopés) est-il pertinent dans le modèle Kratix **natif** actuel ? Et si oui, comment l'implémenter en respectant les pratiques de la plateforme (zéro code par-promesse, data-driven, un seul moteur GitOps, images pinnées) ?
>
> **Verdict en une ligne** : **NON à la hiérarchie de chemins dans le statestore** (redondante, coûteuse, consommée par personne) ; **OUI à une préparation minimale du vrai routage** — la **sélection de Destination par labels**, primitive native déjà exercée en prod — le jour où une 2ᵉ Destination applicative existera physiquement. Un piège actuel est identifié (le pin `environment: platform` au niveau Promise **bloque** tout routage par claim) et un jeu d'objectifs conditionnels RT0–RT3 est fourni.
>
> Analyse en lecture seule, 2026-07-10. Aucun manifeste modifié.

---

## 1. L'ancien système, précisément (3 strates historiques)

### 1.1 Strate 1 — le tout premier statestore (fév. 2026, racine `self-prov`)

Trace résiduelle dans le repo racine (fichiers aujourd'hui supprimés, `git log -- payment/` : dernier commit 2026-02-09, messages `Update from: namespace-bootstrap-…​.payment-5058f`) : des Destinations **nommées par équipe/provider** (`payment/`) écrivaient directement dans le repo racine (`payment/{dependencies,resources}/`, `kratix/resources/`). Premier essai, vite abandonné.

### 1.2 Strate 2 — le modèle `Kratix/` + `platform-control/` (le vrai routage hiérarchique, décommissionné 2026-06-27)

C'est LE système visé par la question. Quatre mécanismes emboîtés :

**a) Topologie multi-statestore / multi-Destination** (`Kratix/Config/global/kratix/`) :

- **4 GitStateStores** sur le même repo `kratix-statestore`, différenciés par préfixe : `state/dev`, `state/staging`, `state/prod`, `state/platform`.
- **~12 Destinations** rangées par domaine (`platform/`×4 dont `prod-cell-01`, `identity/`, `backstage/`, `data/`×3, `infra/`×3), chacune avec `spec.path: <cell>/<domaine>` et **6 labels de taxonomie** :

```yaml
# Kratix/Config/global/kratix/destinations/infra/infra-dev.yaml
kind: Destination
metadata:
  name: infra-dev
  labels: { env: dev, domain: infra, compliance: standard, region: fr-par, cell: cell-01, risk: low }
spec:
  path: cell-01/infra
  stateStoreRef: { name: kratix-dev, kind: GitStateStore }
```

Chemin résultant : `state/<env>/<cell>/<domaine>/{resources,dependencies}/…` (documenté dans `Kratix/Config/global/ARCHITECTURE.md`, § « State store (structure) »). Invariant affiché : « Split par domaine = Destination + path ».

**b) Selectors 8-dimensions écrits par les pipelines** (ex. `platform-control/kratix/promises/platform/product-onboarding/…/pipeline.sh:716`) :

```yaml
- directory: product-onboarding-<provider>-<product>
  matchLabels:
    env: platform
    domain: platform
    cell: cell-platform
    product: product-onboarding
    scope: shared
    compliance: standard
    region: fr-par
    risk: low
```

**c) Le contrat de routage partagé** `platform-control/kratix/promises/platform/_shared/lib/platform_contract.sh` (407 lignes) :

- ConfigMap **`platform-routing-matrix`** (`providers.yaml` + `products.yaml` + `version`/`checksum`) lu au runtime par chaque pipeline (kubectl ou curl+SA token) ;
- **`scope: shared | multi-env`** par produit — c'est le segment `shared` de la question : `platform_contract_resolve_destination_env_for_scope()` route un produit `shared` (non env-scopé, ex. identité) vers `PLATFORM_SHARED_ENVIRONMENT` (défaut `dev`), un produit `multi-env` vers son `executionEnvironment` ;
- ConfigMap **`team-cell-map`** : équipe→cellule (`platform_contract_resolve_destination_cell`) ;
- **chemins ergonomiques des child-claims** : `claims/<provider>/<product>/<claim>.yaml` (`platform_contract_child_claim_path`) + annotations de lignage `platform.kratix.io/{product-id, source-product-id, parent-claim-*}` ;
- côté portail : claims cibles `kratix/resources/products/<provider>/<product>/claims` dans les team-repos.

**d) Une flotte ArgoCD dédiée** : AppProjects `kratix-execution`, `kratix-claims-<team>`, AppSets `appset-claims`/`appset-workloads`… (ARCHITECTURE.md § 3).

### 1.3 Strate 3 — `new-cluster/promise-standard/` (l'intermédiaire, lui aussi décommissionné)

Version rationalisée du même principe : `lib/route.sh` (**`resolve_destination_selectors`** lit la ConfigMap `routing-matrix`, clé `selectors_<key>` au format CSV `k=v,k2=v2` ; fallback bootstrap `environment=platform` ; traçabilité `status.routing{version,checksum,source}` ; **`add_directory_route DIR KEY`** pour router un sous-répertoire de `/kratix/output`). Règles R-RT-1..4 du PROMISE-STANDARD ; le R-RT-4 notait déjà : « le découpage en roots `{product, identity, access, backstage}` est **hérité du modèle d'onboarding** ; **non requis** pour une promise de provisioning simple. En POC : sorties à plat ». Phase B jamais atteinte : la matrice n'a jamais contenu que `selectors_default: "environment=platform"`.

**Bilan de l'ancien système** : la hiérarchie `provider/produit/env/consumer` existait à DEUX niveaux — (1) la **topologie de Destinations** (env×cell×domaine, portée par labels + `spec.path`) et (2) des **chemins intra-output composés par les pipelines** (provider/product pour les child-claims). Le tout exigeait : 2 ConfigMaps runtime à maintenir, du RBAC de lecture par pipeline, une lib shell vendorisée dans chaque image, ~12 Destinations, une flotte d'apps ArgoCD — pour un cluster unique.

---

## 2. Le modèle natif actuel (état vérifié)

### 2.1 Topologie

- **1 GitStateStore** `default` → `Younesic/kratix-state`, `path: .` (`platform-gitops/bootstrap/manifests/kratix-config/gitstatestore.yaml`).
- **2 Destinations** : `worker-1` (label `environment: platform`, `path: worker-1`) = le cluster applicatif ; `backstage` (label `environment: backstage`, `path: backstage`) = le catalogue (lu par le provider GitHub de Backstage, **pas** par ArgoCD).
- **1 app ArgoCD** `kratix-destination` (wave 3) : watch `kratix-state/worker-1` en récursif (`exclude: "**/.kratix/**"`), applique sur le cluster (`bootstrap/apps/kratix-destination.yaml`).

### 2.2 Structure réelle du statestore (clone du 2026-07-10)

```
worker-1/
  dependencies/<promise>/5058f/static/<promise>-dependencies.yaml
  resources/default/<promise>/<claim>/<pipeline>/5058f/object.yaml        # feuilles
  resources/default/team-space/teamspace2/instance-configure/5058f/children/{workspace,teamaccess}.yaml  # compounds
backstage/
  dependencies/<promise>/promise-configure/5cfaf/backstage/{template,skeleton/…}
  resources/default/<promise>/<claim>/…/backstage/<claim>.yaml
```

Constats : (1) le segment `<namespace>` vaut **toujours `default`** (les renderers officiels forcent `namespace: default` — gotcha connu du repo) → il ne porte **aucune** information consumer ; (2) `5058f`/`5cfaf` = hash de WorkloadGroup, illisible par construction ; (3) les **child-claims des compounds sont déjà visibles** à un chemin déterministe (`…/<parent-claim>/…/children/<nom-logique>.yaml`) ; (4) chaque commit est une piste d'audit (`Update from: keycloak-group-acme-instance-configure-23635.worker-1-5058f`, auteur `kratix-platform`).

### 2.3 Le point unique de routage (généricité en place)

- `new-cluster/native/scaffold/defaults.env` : `DESTINATION_SELECTOR=environment=platform` — consommé par `plugin_lib.add_common_args` puis `wire_platform_conventions` → `kratix update destination-selector` (`plugin_lib.py:110`). **Toutes** les promesses (11 manifestes dans `platform-gitops/bootstrap/manifests/kratix-promises/`, vérifié par grep) portent `spec.destinationSelectors: [{matchLabels: {environment: platform}}]`. La factory embarque les mêmes plugins → même point unique.
- Le conteneur partagé `backstage-component` exerce **déjà en prod** la primitive native de routage fin : `generate.py:117` écrit un selector **scopé par répertoire** — `DestinationSelector(directory="backstage", match_labels={environment: backstage})` — qui envoie le sous-dossier `backstage/` de `/kratix/output` vers l'autre Destination pendant que le reste suit la promesse.

### 2.4 Les 3 axes du routage existent déjà comme DONNÉES (pas comme chemins)

| Axe | Où il vit aujourd'hui |
|---|---|
| **provider** | curation `spec.curation.provider` → annotation `platform.kratix.io/provider` (forcée serveur par O4, propagée par bc sur Template/fiche/claim) |
| **consumer** | `OWNER_FIELD` (`spec.team`) + label hérité `platform.example.io/component-of-owner` posé par le compound-renderer (`render.py:53-54`) ; O6 (backlog acté) = label sélectionnable `platform.kratix.io/owner=team-<slug>` sur toute ressource provisionnée |
| **env** | champ de spec du produit (ex. `workspace.environment`, enum dev/staging/prod) |

---

## 3. Sémantique native Kratix (vérifiée, sources citées)

Faits vérifiés sur le **CRD Destination vendorisé** (`platform-gitops/bootstrap/manifests/kratix/install.yaml` — la vérité de la version pinnée déployée), la doc officielle et le source upstream :

1. **Chemin d'écriture natif** : `<statestore.path>/<destination.path>/resources/<ns>/<promise>/<claim>/<pipeline>/<id>/` et `…/dependencies/<promise>/<pipeline>/<id>/` ([docs.kratix.io — Destination](https://docs.kratix.io/main/reference/destinations/intro)).
2. **`spec.filepath.mode`** ∈ { `nestedByMetadata` (défaut), `aggregatedYAML`, `none` } — **IMMUTABLE** (`x-kubernetes-validations: self == oldSelf`, install.yaml l. 265-289). NB : le mode s'appelle `nestedByMetadata` dans la version déployée (pas `nameAndNamespace`, nom d'une itération antérieure).
3. **Mode `none` = contrôle total du chemin par le pipeline** : vérifié dans le source upstream ([workplacement_controller.go](https://github.com/syntasso/kratix/blob/main/internal/controller/workplacement_controller.go)) — `workload.Filepath = filepath.Join(pathPrefix, workload.Filepath)` : l'arborescence relative de `/kratix/output` est préservée telle quelle sous `<destination.path>/`, le nettoyage étant tracé dans `.kratix/`. C'est la primitive qu'utiliserait une hiérarchie ergonomique… au prix de garantir soi-même l'unicité des chemins (ce que `nestedByMetadata` garantit par construction).
4. **Précédence des selectors** ([docs — Managing Multiple Destinations](https://docs.kratix.io/main/reference/destinations/multidestination-management)) : `Promise spec.destinationSelectors` **>** `destination-selectors.yaml` du workflow promise **>** celui du workflow **resource** (= par claim). « In the event of a label conflict, the Promise spec.destinationSelectors take precedence over any dynamic scheduling. » → **le routage par claim est natif** (le pipeline resource/configure écrit `/kratix/metadata/destination-selectors.yaml`), mais une clé pinnée au niveau Promise est **inoverridable**.
5. **Clé `directory:`** dans `destination-selectors.yaml` : scope les matchers à un sous-répertoire de `/kratix/output` **en ignorant** les selectors de la Promise pour ces fichiers (le mécanisme bc/backstage actuel).
6. **Défauts sans selector** : dependencies → **toutes** les Destinations ; resources → une Destination **aléatoire**. Garde-fou par Destination : `strictMatchLabels: true` (install.yaml l. 331-339).
7. Multi-destination Syntasso/SKE : le pattern officiel = **une Destination par cluster/environnement, sélection par labels** ; jamais une Destination par équipe consommatrice ni par produit ([docs — multidestination](https://docs.kratix.io/main/reference/destinations/multidestination-management)).

---

## 4. Analyse honnête : POUR / CONTRE la hiérarchie de chemins

### 4.1 POUR (ce que l'ancien système apportait réellement)

1. **Lisibilité humaine du repo d'état** : `git log -- state/prod/cell-01/data/` répond « qu'est-ce qui a changé en prod/data ? » sans outillage. Le chemin natif (`worker-1/resources/default/<promise>/<claim>/<pipeline>/5058f/`) exige de connaître promise+claim et tolère les hashes.
2. **Audit/DR par axe métier** : découpage par env/domaine = restauration ou revue **partielle** (re-apply d'un sous-arbre), blast-radius par répertoire, diffs de PR bornés à un domaine.
3. **RBAC Git par chemin** : CODEOWNERS/protections par sous-arbre (ex. `state/prod/**` sous revue renforcée) — impossible à exprimer sur des hashes.
4. **Multi-destination réel** : quand dev/staging/prod seront des clusters distincts, il FAUDRA bien router. L'ancien modèle avait au moins posé la taxonomie (env, cell, domain…).
5. **Le segment `shared` posait une vraie question** : où vivent les produits non env-scopés (identité) ? La réponse « control-plane » reste valable.
6. **Traçabilité de lignage des child-claims** (`product-id`, `source-product-id`, `parent-claim-*`) : une bonne idée… dont l'équivalent existe déjà (labels officiels `kratix.io/component-of-*` + `component-of-owner`).

### 4.2 CONTRE (pourquoi c'est le mauvais outil aujourd'hui)

1. **Personne ne consomme cette ergonomie.** Les humains lisent le **portail** (fiches, graphe hasPart/dependsOn, onglet Kubernetes live, statuts) — c'est un invariant de design de la plateforme (« les humains lisent le portail, pas kratix-state »). Les machines lisent : ArgoCD (récursif, indifférent aux chemins), le provider Backstage (glob ancré). L'**intention** humaine, elle, est déjà dans un repo ergonomique et gouverné : `portal-templates/requests/<promesse>/<nom>/claim.yaml` (PR + merge humain). Le statestore est un **format interne de réconciliation**, pas une UI.
2. **Redondance avec les données existantes.** provider/consumer/env sont des labels/annotations **requêtables** (`kubectl get … -l platform.kratix.io/owner=team-X` une fois O6 livré ; facettes marketplace par provider ; env dans la spec). Encoder ces axes dans des chemins = **dupliquer une vérité** qui vit déjà au bon endroit, avec le risque classique de divergence (le bug `group2`/teamspace2 a montré ce que coûte une donnée re-saisie au lieu de dérivée).
3. **Le coût technique est disproportionné** :
   - `filepath.mode` est **immutable** → passer worker-1 en mode `none` = recréer la Destination + re-scheduler tous les Works + re-pointer l'app ArgoCD + re-ancrer le glob catalogue Backstage (`/backstage/resources/**/backstage/*.yaml`, gotcha canaries vécu 2h) ;
   - en mode `none`, l'**unicité des chemins** devient NOTRE problème (deux claims → même chemin = écrasement silencieux), exactement ce que `nestedByMetadata` élimine ;
   - il faudrait réintroduire une **matrice de routage runtime** (2 ConfigMaps + RBAC + lib vendorisée dans les images pinnées = rebuilds) — l'artefact dont la plateforme vient de se débarrasser en passant au natif ;
   - les renderers officiels (helm-resource-configure, from-api-to-crossplane-claim, from-api-to-operator) écrivent `/kratix/output` **à plat** : imposer une arborescence par claim = wrapper ou conteneur post-render sur CHAQUE pipeline → contraire au levier « renderers officiels + zéro image par promesse ».
4. **La combinatoire ne scale pas en chemins ni en Destinations.** N providers × M produits × E envs × C consumers : avec 5 providers, 10 produits, 3 envs, 30 squads → 4 500 feuilles théoriques. Une Destination par feuille est absurde (4 500 Destinations + apps ArgoCD) ; une Destination par env×cell = **3–6** (le bon niveau, cf. § 5). Et un chemin à 4 segments dans UNE Destination n'est qu'un rangement cosmétique : ArgoCD applique pareil, kubectl ne le voit pas, le portail ne le lit pas.
5. **L'ancien système lui-même l'avait avoué** : R-RT-4 `[DEFERRED]` — « le découpage en roots est hérité du modèle d'onboarding, non requis […] sorties à plat » ; la Phase B (matrice product-id→provider/env/cell) n'a **jamais été activée**. Le routage hiérarchique était un échafaudage pour un multi-cluster qui n'existait pas — il n'existe toujours pas (1 cluster, 1 Destination applicative).
6. **Piège actuel identifié (fait nouveau de cette analyse)** : les 11 promesses pinnent `environment: platform` **au niveau Promise** ; or la précédence upstream rend ce pin **inoverridable par claim**. Le jour du multi-env, le routage par claim sur la clé `environment` sera silencieusement impossible sans re-générer les promesses. Ce n'est PAS un argument pour les chemins — c'est le vrai chantier de routage à préparer (RT1).

### 4.3 Réponses point-à-point aux « POUR »

| Besoin légitime | Réponse au bon niveau (sans hiérarchie de chemins) |
|---|---|
| Lire « ce qui a changé en prod » | Destination par env (`spec.path: worker-prod`) → `git log -- worker-prod/` suffit ; PLUS le repo d'intention `portal-templates/requests/` déjà ergonomique |
| Audit par équipe | O6 (`platform.kratix.io/owner` label sélectionnable) + graphe portail ; `git log -- worker-1/resources/default/<promise>/<claim>/` marche déjà |
| RBAC Git par env | protection de branche/CODEOWNERS sur `worker-<env>/**` (granularité Destination, pas claim) |
| Multi-cluster futur | **labels de Destination + selectors par claim** (natif, § 3.4) — pas des chemins |
| Produits `shared`/non env-scopés | ils gardent le pin control-plane `environment: platform` (worker-1 EST la destination « shared ») — zéro segment nécessaire |
| Lignage des child-claims | déjà couvert : `children/<nom>.yaml` sous le claim parent + labels `kratix.io/component-of-*` + `component-of-owner` + graphe hasPart |

---

## 5. VERDICT

**1) Pertinence de l'approche hiérarchique par chemins : NON — ne pas la ressusciter.**

La hiérarchie `provider/produit/env/consumer` dans le statestore est une réponse **cosmétique** à des besoins déjà couverts par des mécanismes plus forts (portail pour la lecture humaine, labels/annotations pour la requête et la gouvernance, `requests/` pour l'intention auditée), et une réponse **au mauvais niveau** au seul besoin réel (le multi-destination), qui se traite nativement par **labels de Destination**, pas par chemins. Son coût (mode filepath immutable, unicité des chemins à notre charge, matrice runtime à maintenir, wrappers autour des renderers officiels, rebuilds d'images pinnées) viole le ratio valeur/complexité qui a justifié le décommissionnement de l'ancien modèle. Le fait que la Phase B de l'ancienne matrice n'ait jamais été activée est l'aveu empirique : **l'ergonomie des chemins git n'a jamais manqué à personne**.

**2) Ce qui EST pertinent (la part de vrai de l'ancien système) : la sélection de Destination par labels, à granularité env×cell — à préparer, pas à implémenter aujourd'hui.**

Trois idées de l'ancien monde méritent d'être conservées **sous forme native** :
- **Destination = env(×cell), jamais plus fin** (ni provider, ni produit, ni consumer) — c'est aussi le pattern Syntasso ;
- **le produit déclare son scope** (`shared` → reste sur le control-plane ; env-scopé → suit son champ d'env) — en données de la promesse, pas en matrice runtime ;
- **un point de décision unique et data-driven** — il existe déjà (`defaults.env` → `plugin_lib`), il faut juste le protéger du piège de précédence.

**Déclencheur d'implémentation** : l'enregistrement d'une **2ᵉ Destination applicative réelle** (cluster ou env physique distinct). Avant ce jour, tout travail de routage est du YAGNI ; le plan ci-dessous est écrit pour être exécutable ce jour-là sans dette d'ici là.

---

## 6. Plan conditionnel RT0–RT3 (format OPx/DoD — NE PAS lancer avant le déclencheur)

> Périmètre de généricité : **un seul point de code** par changement (plugin_lib/defaults.env pour la pose, un conteneur partagé pour le dynamique), **zéro code par-promesse**, primitives officielles uniquement, images re-pinnées par digest. Preuves dans `Objectives/routing/proofs/`.

### RT0 — Décision de granularité gravée (doc-only, faisable dès maintenant, ~0 coût)
Graver dans `PROMISE-STANDARD.md` (section « Placement ») : (a) **Destination = env×cell**, chemin = `worker-<env>[-<cell>]`, même GitStateStore `path: .` ; (b) provider/produit/consumer = **labels/annotations, jamais des segments de chemin** ; (c) `filepath.mode` reste `nestedByMetadata` (l'unicité par construction prime sur l'esthétique) ; (d) produits non env-scopés (`shared`) = pin control-plane `environment: platform`.
**DoD** : section publiée + renvoi depuis `scaffold/README.md` ; aucune promesse modifiée.

### RT1 — Dé-conflit du selector de base (le fix du piège de précédence)
> **✅ EXÉCUTÉ 2026-07-16** (par anticipation, décision user « déroule la chaîne »). Écart
> assumé vs le plan : le knob n'est PAS un flip global de defaults.env mais **`spec.placement`
> au PromiseRequest** (v0.8.2 — le produit déclare son scope DANS SON CLAIM, la donnée durable ;
> défaut omis = `environment=platform` → DoD (d) tenu par construction). 5 produits flippés
> `fleet=apps` (workspace, team-space, workspace-ks1prov, rabbit, sandbox — PRs #40–44, diff =
> 1 ligne chacun) ; identité/factory/database inchangés ; worker-1 = les 2 labels. Preuves :
> `backstage-platform/Objectives/routing/proofs/RT1-{evidence.txt,RESULTS.json}`.
Aujourd'hui `DESTINATION_SELECTOR=environment=platform` est posé au niveau **Promise** → inoverridable par claim (précédence upstream, § 3.4). Le jour J : les promesses de produits **env-scopés** ne doivent plus pinner `environment` au niveau Promise. Changement au point unique : `defaults.env` passe à une clé de flotte non conflictuelle (ex. `fleet=apps`, posée en label sur TOUTES les Destinations applicatives) ; les promesses control-plane/`shared` gardent en plus `environment: platform` (knob par promesse via flag `--destination` existant). Rebuild factory + re-pin digest + régénération des promesses env-scopées (flux update éprouvé : re-run claims → branches `promise/*` → merges humains).
**DoD mesurable** : (a) une promesse env-scopée régénérée ne porte plus `environment` dans `spec.destinationSelectors` mais `fleet: apps` ; (b) ses claims existants restent schedulés sur worker-1 (non-régression : worker-1 labellisé `fleet=apps` + `environment=platform`) ; (c) `kratix-canary` sain sur toutes les Destinations ; (d) les promesses `shared` inchangées.

### RT2 — Routage par claim, data-driven et générique (la vraie « Phase B », en natif)
Un produit env-scopé route **par la donnée du claim** : un step partagé (extension du conteneur bc, même pattern que `OWNER_FIELD`/`route_catalog_to_backstage` déjà en prod — `generate.py:117`) lit `ENV_FIELD` (défaut `spec.environment`, knob ENV par promesse, hors CRD = zéro schéma touché) et écrit `/kratix/metadata/destination-selectors.yaml` → `[{matchLabels: {environment: <valeur>}}]` au workflow **resource/configure**. Compounds : rien de spécial — les child-claims appliqués au cluster sont routés par LEURS promesses via le même step (l'env descend par le câblage de recette existant, fix/derive). `strictMatchLabels: true` sur les Destinations de prod (un claim sans env résolu ne tombe jamais en prod par tirage aléatoire).
**DoD mesurable** : (a) claim `environment: dev` → objets sous `worker-dev/resources/…`, claim `prod` → `worker-prod/…` (preuve git) ; (b) AUCUNE image par promesse ajoutée (le step vit dans bc, re-pin unique) ; (c) un claim compound → enfants routés selon leur env hérité ; (d) claim sans env → reste sur le control-plane (fallback explicite, jamais aléatoire — prouvé avec `strictMatchLabels`).

### RT3 — Boucle GitOps par Destination (le pendant ArgoCD, borné)
Une app ArgoCD par Destination applicative (3–6, pas 4 500) : dupliquer `kratix-destination.yaml` par env (path `worker-<env>`, `destination.server` du cluster cible) — ou ApplicationSet generator=list si ≥4. Le catalogue Backstage est **hors périmètre** (Destination `backstage` inchangée).
**DoD mesurable** : (a) N Destinations = N apps Synced/Healthy ; (b) suppression d'un claim → prune dans la bonne Destination uniquement ; (c) le README kratix-config documente « ajouter un env = 1 Destination + 1 app + labels » (2 fichiers, zéro code).

**Explicitement écarté** (avec raison) : `filepath.mode: none`/chemins par pipeline (unicité à notre charge + mode immutable + wrappers sur renderers officiels) ; Destination par provider/produit/consumer (combinatoire § 4.2.4) ; matrice de routage runtime (ConfigMap+RBAC+lib = la dette dont on sort) ; renommage/symlinks côté statestore (2ᵉ écrivain du repo d'état = conflit avec Kratix, seul auteur légitime).

---

## 7. Sources

- Ancien modèle : `platform-control/kratix/promises/platform/_shared/lib/platform_contract.sh` ; `platform-control/kratix/promises/platform/product-onboarding/…/pipeline.sh` (l. 705, 716-724) ; `Kratix/Config/global/ARCHITECTURE.md` ; `Kratix/Config/global/kratix/{gitStateStore.yaml, destinations/**}` ; `new-cluster/promise-standard/{lib/route.sh, manifests/routing-matrix.yaml, README.md, PROMISE-STANDARD.md}` (R-RT-1..4).
- Modèle actuel : `platform-gitops/bootstrap/manifests/kratix-config/{gitstatestore,destination,destination-backstage}.yaml` ; `platform-gitops/bootstrap/apps/kratix-destination.yaml` ; `new-cluster/native/scaffold/{defaults.env, plugin_lib.py}` (l. 48, 110) ; `new-cluster/native/_shared/backstage-component/scripts/generate.py` (l. 115-119) ; `new-cluster/native/_shared/compound-renderer/scripts/render.py` (l. 50-54, 264-281) ; clone lecture seule de `Younesic/kratix-state` (2026-07-10) ; grep `destinationSelectors` sur les 11 promesses de `platform-gitops/bootstrap/manifests/kratix-promises/`.
- Upstream (version pinnée + docs) : CRD Destination vendorisé `platform-gitops/bootstrap/manifests/kratix/install.yaml` (filepath.mode enum + immutabilité l. 265-289, strictMatchLabels l. 331-339) ; [docs.kratix.io — Destination](https://docs.kratix.io/main/reference/destinations/intro) ; [docs.kratix.io — Managing Multiple Destinations](https://docs.kratix.io/main/reference/destinations/multidestination-management) (précédence Promise > workflows, clé `directory`, défauts all/random) ; [syntasso/kratix — workplacement_controller.go](https://github.com/syntasso/kratix/blob/main/internal/controller/workplacement_controller.go) (mode `none` préserve les chemins relatifs du pipeline).
