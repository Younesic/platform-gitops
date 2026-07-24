<!-- CANONIQUE depuis 2026-07-18 (BR14) — ex-emplacement : new-cluster/native/PROMISE-STANDARD.md (stub de redirection) -->
# Standard d'écriture des Promises — le CLI officiel Kratix comme scaffold

> **Principe : on n'invente aucun outil, et on ne construit AUCUN renderer.** Pour (presque) tout produit,
> une variante **`kratix init <X>-promise`** **génère la CRD depuis la source ET câble un renderer PARTAGÉ
> maintenu par Syntasso**. Zéro code maison pour le provisioning. Seul « code maison » = l'image partagée
> `backstage-component` (fiche Backstage), branchée par une commande officielle.
> Tout ici est **vérifié** (source `kratix-cli/cmd` + `stages/`, doc, `--help`).

---

## 0. Choisir la variante `init` (elle câble un renderer partagé — tu ne construis rien)
Chaque variante consomme une **source** et **auto-câble le renderer** (vérifié dans le source) :

| Source du produit | Commande | Renderer partagé câblé (auto) |
|---|---|---|
| **Chart Helm** (cas par défaut — y compris manifestes bruts emballés en chart) | `kratix init helm-promise --chart-url oci://harbor…/x --chart-version <v> -k <Kind>` | `helm-resource-configure` |
| Crossplane (XRD + Composition) | `kratix init crossplane-promise --xrd … --compositions …` | `from-api-to-crossplane-claim` |
| Operator k8s **existant** (a déjà sa CRD) | `kratix init operator-promise --operator-manifests … --api-schema-from <CRD>` | `from-api-to-operator` |
| Module Terraform | `kratix init tf-module-promise --module-source …` | stage terraform |
| Composant Pulumi (schema.json) | `kratix init pulumi-component-promise --schema …` | stage pulumi |
| **Bespoke** (logique vraiment sur-mesure, rare) | `kratix init promise` + `kratix add container` (image maison) | — (tu écris le conteneur) |

**Règle d'or : ne construis PAS de renderer.** Prends la variante qui colle à ta source.
Un **namespace + quota + RBAC = des manifestes → un petit chart Helm → `helm-promise`**. Pas de XRD
(Crossplane = overkill pour un namespace), pas de conteneur bash maison (ça ne scale pas : 1 image par
promesse à maintenir).

## 1. L'API — riche selon la variante
- Variantes à **schéma riche** (`crossplane-promise` via l'XRD, `operator-promise` via la CRD existante,
  `pulumi-component-promise` via le schema.json) → **`enum`/`required` repris tels quels → ZÉRO édition manuelle.**
- `helm-promise` → l'API est **déduite des `values`** en **types de base** (pas d'`enum`) → pour une API
  stricte, **un petit hand-edit du CRD** (ajouter `enum`/`default`/`required`) **après** génération. C'est le
  **seul** geste manuel, et il est **spécifique à helm-promise**.
- Le fond : un `enum` est de la **connaissance métier** — **aucun** outil ne l'invente. Il se déclare **une
  fois**, soit dans la source riche (XRD/CRD/schema), soit en hand-edit (helm).

## 2. Le mapping (provisioning) = le renderer PARTAGÉ — tu ne l'écris pas
- La variante `init <X>-promise` **câble déjà** le bon renderer (`helm-resource-configure`,
  `from-api-to-crossplane-claim`, `from-api-to-operator`…). **Tu n'écris rien.**
- Le renderer **tire la source au runtime** (helm : `CHART_URL`/`CHART_VERSION` en ENV → pull du chart depuis
  Harbor) et rend les manifestes.
- Un `kratix add container` avec **image maison** = **uniquement** pour de la logique **vraiment bespoke**
  (le 20 %), **jamais** pour du helm/crossplane/operator.

## 3. Le placement — `kratix update destination-selector KEY=VALUE`
`kratix update destination-selector environment=platform` (vérifié). **Jamais** de routage maison.

**Granularité gravée (RT0, décision 2026-07 — analyse complète :
`new-cluster/native/DESTINATION-ROUTING-ANALYSIS.md`)** :
- **Une Destination = un env(×cell), jamais plus fin** (ni provider, ni produit, ni consumer —
  pattern Syntasso). Chemin `worker-<env>[-<cell>]`, même GitStateStore `path: .`.
- **provider / produit / consumer = labels & annotations, JAMAIS des segments de chemin** du
  statestore (`platform.kratix.io/provider`, `component-of-owner`, champ d'env de la spec —
  requêtables ; le statestore est un format interne de réconciliation, pas une UI : les humains
  lisent le portail et `portal-templates/requests/`).
- **`filepath.mode` reste `nestedByMetadata`** (défaut) : l'unicité des chemins par construction
  prime sur l'esthétique ; le mode est IMMUTABLE — en changer = recréer la Destination.
- **Produits non env-scopés (« shared »)** : pin control-plane `environment: platform` —
  worker-1 EST la destination « shared », zéro segment nécessaire.
- ✅ **Piège de précédence — RT1 EXÉCUTÉ (2026-07-16, par anticipation sur décision user)** :
  un selector posé au niveau **Promise** est **inoverridable par claim** (précédence upstream
  Promise > workflow promise > workflow resource) → un pin Promise `environment: <x>`
  bloquerait le routage par claim en multi-env. Résolu : **le produit déclare son scope dans
  SON claim** — `PromiseRequest.spec.placement` (≥ v0.8.2, UNE paire `label=valeur`) → flag
  `--destination` commun aux 4 plugins ; **omis = `environment=platform`** (control-plane/
  « shared » : identité, factory — défaut inchangé) ; **produit applicatif = `fleet=apps`**.
  worker-1 porte les DEUX labels (une future Destination d'env portera `fleet=apps` +
  `environment=<env>` — le routage par claim (RT2, à faire au déclencheur) départagera par
  `environment`, clé désormais LIBRE au niveau Promise des produits). RT2/RT3 restent
  conditionnels à la 2ᵉ Destination réelle — plan et DoD dans l'analyse.

## 4. Compound — champ `spec.requiredPromises`
`spec.requiredPromises` (dépendance/gating) **+** le workflow émet des **claims enfants**. Champ de `promise.yaml`, pas de commande dédiée.

## 5. La fiche Backstage — image partagée `backstage-component`
- Promise Configure → `Component` `kratix-promise` (mode `promise`) ; Resource Configure → `Component`
  `kratix-resource` du provisionné (mode `resource`). Câblés via `kratix add container`.
- Le **Template** est auto-généré côté Backstage depuis le schéma de la CRD (provider Terasky).
- Image partagée : `new-cluster/native/_shared/backstage-component/`.

## 6. Identité = `team-<slug>` partout (convention)
Groupe Keycloak `team-<slug>` · owner Backstage `group:default/team-<slug>` · contexte Kratix `team-<slug>`.

## 7. Versionnement & gouvernance = Harbor + pin
- **Images** (backstage-component, renderer bespoke éventuel) : Harbor, épinglées par **digest** `@sha256`.
- **Charts Helm** (la source d'un produit) : **poussés & versionnés dans Harbor** (OCI). La promesse
  **épingle** `--chart-version` = le **pin de gouvernance** (comme un SHA git). Changement source =
  **nouvelle version** + **bump** de la promesse (PR revue). Immuabilité stricte = **tags immuables Harbor**
  (ou digest). Le renderer a besoin d'un **accès pull Harbor** au runtime.
- **Jamais** de source mutable non épinglée (sinon un changement casse **silencieusement** les promesses).

## 8. Day-2 = `configure` ET `delete`
Effet impératif sans CR : `kratix add container resource/delete/<p> --image …`. Les sorties déclaratives (CR k8s/Crossplane) sont prunées automatiquement → pas de `delete`.

## 9. Promesses OPERATOR (moteur 4 de la factory — prouvé E2E sur `rabbit`, 2026-07)

**Modèle** : `kratix init operator-promise` (statut **Preview** upstream — pin CLI v0.17.0 +
tests d'équivalence = le filet). La **CRD désignée EST le contrat** : copiée telle quelle
(spec **et** status) dans l'API de la promesse, version **STORAGE** retenue. Les manifestes
ENTIERS de l'opérateur deviennent **`spec.dependencies` INLINE** → l'opérateur est installé
**1×/Destination** ; N claims = N CRs. Source = **repo git à ref PINNÉE** (tag semver ou SHA)
+ `path` ; via le portail : `PromiseRequest.spec.source{url, version, path, apiSchemaFrom}`.

- **Renderer** = l'officiel `from-api-to-operator`, épinglé **par DIGEST sur notre miroir
  Harbor** (`OPERATOR_RENDERER_IMAGE` de `scaffold/defaults.env`) — ⚠️ vécu : le tag ghcr
  `v0.2.2` documenté était un **tag fantôme** (ImagePullBackOff, et un Job en IPBO ne FAIL
  jamais → pipeline coincé : `kubectl delete job` + `kratix.io/manual-reconciliation=true`).
  Comportement (source lu) : CR = **nom du claim**, **`namespace: default` FORCÉ** (miroir du
  gotcha crossplane), labels+annotations du claim **propagés au CR**, **spec passthrough
  intégral**, aucun status writeback.
- **Curation de l'API** : `spec.source.omit[]` (PromiseRequest ≥ v0.8.1) = le plugin exécute
  l'officiel `kratix update api --property <champ>-`. **BR5 (≥ v0.8.3) : chemins POINTÉS admis**
  (`override.statefulSet` = retrait NESTED ; le reste du parent reste, et le plugin nettoie le
  `required` orphelin que le CLI v0.17.0 laisse — vérifié par test, sinon objet insatisfiable).
- **Co-mainteneurs (BR15, 2026-07-18)** : `spec.curation.maintainers: "team-b,team-c"`
  (**CSV** — le CRD curation est une map de STRINGS) → annotation
  `platform.kratix.io/maintainers` propagée par bc (passthrough générique, fiche+Template).
  Un co-mainteneur RÉGÉNÈRE sans fork ni 403 (verdict `allow-maintainer`) et **la lignée ne
  bouge pas** : le forçage O4 pose alors `provider = celui de la CIBLE`, jamais l'auteur.
  Durabilité : la donnée DURABLE vit dans le CLAIM (`curation.maintainers`) — une annotation
  posée sur un manifeste GÉNÉRÉ est perdue à la régénération (leçon KS6b).
- **Gros opérateurs (BR6 — décision instrumentée, 2026-07-18)** : mesures réelles —
  prometheus-operator **4 399 Ko** (10 CRDs, plus gros doc SEUL 811 Ko) · grafana-operator
  **772 Ko** (13 CRDs) · minio-operator **255 Ko** rendu par `kubectl kustomize` (2 CRDs —
  corrige « écarté, kustomize » d'OP1 : on VENDORISE LE RENDU, génération complète prouvée,
  promesse 563 Ko). **Amplification mesurée deps→Promise ≈ ×2,2** (minio 255→563 ; rabbit
  342→750) → la garde `OPERATOR_DEPS_MAX_KB=800` reste LE DÉFAUT : au-delà, la Promise
  inline approche le mur etcd (~1,5 Mo) — `--max-deps-kb` ne fait que déplacer le refus
  vers l'admission. **Décision (i)** : limite FERME + refus guidé enrichi (2 voies
  concrètes). **Voie (ii) écrite, AU DÉCLENCHEUR** (premier vrai besoin > seuil) :
  deps-par-workflow PARTAGÉ — un conteneur générique env-paramétré (GIT_URL/REF/PATH, même
  clone pinné que la factory) émet les manifestes au promise-configure → statestore : aucun
  objet etcd géant (plus gros doc prometheus 811 Ko < 1 Mo/objet, apply SSA), AUCUNE image
  par promesse (le levier tient). ⚠️ Robustesse vécue : la CRD prometheus contient un
  scalaire YAML 1.1 `=` nu → SafeLoader patché (plugin_lib + derive_server), sinon
  traceback AVANT la garde. ⚠️ vécu : les **défauts PROFONDS** d'une
  CRD tierce (ex. `override` de RabbitMQ) sont matérialisés par rjsf → des requireds imbriqués
  bloquent la Review d'un formulaire VIERGE → **omettre le champ est la correction**, pas des
  rustines de formulaire. Un champ omis n'est jamais posé → défauts de l'opérande.
- **Exports** : `derive_status_schema` (plugin_lib, partagé crossplane) lit le status de la
  CRD → annotation `platform.kratix.io/status-schema` → picker LABELLISÉ (V4-2) dans Studio/
  composer ; résolution runtime = **uplift V4-0** (`resolve_from_provisioned` suit
  `status.provisionedResources` → lit la valeur sur le CR réel).
- **Garde de taille** : `OPERATOR_DEPS_MAX_KB=800` (defaults.env, `--max-deps-kb`) — deps
  inline vs objet etcd ~1,5 Mo ; l'app kratix-promises applique en **ServerSideApply=true**
  (pas de doublement last-applied). Trop gros → refus guidé (grafana 771 Ko + 13 CRDs écarté).

**Règles (limites structurelles, toutes constatées)** :
1. **Un opérateur = UNE promesse.** Deux promesses embarquant le même opérateur = deps
   dupliquées qui se disputent les mêmes objets cluster-scoped.
2. **Pas d'homonymes de claims cross-namespace** : le CR atterrit dans `default` → deux
   claims du même nom se percutent (limite partagée avec crossplane).
3. **Visibilité** : fiche/graphe catalogue = **le CR SEUL** (les enfants créés PAR l'opérateur
   ne passent pas par /kratix/output). L'onglet Kubernetes LIVE peut montrer PLUS : **si
   l'opérateur propage les labels du CR à ses enfants** (RabbitMQ le fait), le
   `kubernetes-id` suit → STS/Services/CM visibles. Opérateur-dépendant, jamais garanti.
4. **Console live** : la FAMILLE du groupe tiers (ex. `rabbitmq.com`) doit être ajoutée à
   `customresources-sync` (FAMILIES) + un bloc RBAC `backstage-readonly` — 1 ligne chacun,
   « une ligne par provider, jamais par promesse ».
5. **Ownership d'une instance** : une CRD tierce n'a PAS `spec.team` (OWNER_FIELD) → le
   RequesterTeamPicker (O5) ne se pose pas. **INTERDIT** : `kratix update api --property
   team:string` en direct — le renderer copie le spec ENTIER, et l'admission du CR est
   STRICTE (probe serveur 2026-07-16 : `strict decoding error: unknown field "spec.team"` —
   pas de pruning silencieux avec fieldValidation/SSA) → l'apply de la destination casserait.
   **Patterns admis** : (a) **label owner déclaré AU CLAIM**
   `platform.example.io/component-of-owner: <team>` — le renderer propage les labels au CR
   (owner sélectionnable au cluster, esprit O6) et la fiche bc le consomme (témoin bunny) ;
   (b) **compound wrapper** exposant `team` → l'héritage owner du renderer compound pose le
   même label automatiquement sur les claims enfants.

**Suppression (l'acte le plus destructif du moteur — retirer une CRD supprime TOUS les CRs
du groupe)** : ordre SÛR prouvé sur le témoin = **instances d'abord** (retrait des fichiers
`requests/` — le CR part, l'opérateur RESTE), **puis la promesse** (retrait du manifeste
`kratix-promises/` — deps prunées : opérateur, CRDs, namespace). Le retrait d'une promesse
adoptée est un **acte de gouvernance** : le merge du retrait EST le garde-fou, comme à
l'installation. ⚠️ Supprimer la promesse AVEC des claims vivants = risque **deadlock
PromiseRevision** (le finalizer `revision-cleanup` retire les révisions AVANT la fin des
claims → leurs delete-reconciles bouclent sur « promise revision not found ») ; remède
documenté : recréer une PromiseRevision de secours (`<promise>-recovery`,
`labels {kratix.io/promise-name, kratix.io/latest-revision: "true"}`, `spec.promiseSpec` =
le spec encore lisible, `version` = celle des claims) **puis** forcer un requeue en annotant
les claims (backoff au max après des heures). Rollback = `git revert` du retrait →
l'opérateur revient (destination re-sync).

---

## 10. Encapsulation d'abord (loi 6 / CT3 — hiérarchie des fixes)

**Règle d'or : un champ dont UNE SEULE valeur est valide dans le contexte d'usage ne
s'expose pas.** Il se dérive, se fige, ou prend un défaut + `ui:widget: hidden`.
Le contrat déclaré (requires/provides) est le FILET, pas l'excuse.

**Test de décision** — avant d'exposer un champ, demander :
> « Un demandeur pourrait-il LÉGITIMEMENT mettre une autre valeur ? »
- Non → ne pas l'exposer (défaut + masqué, ou dérivé d'un autre champ). Ex. : `realm`
  (toujours `platform` sur cette plateforme) — vécu CT3 : exposé sur le template User,
  un demandeur pouvait le corrompre pour rien.
- Oui mais UNE valeur est attendue par une autre brique → l'exposer ET déclarer le
  contrat (`requires`/`provides`, annotation `platform.kratix.io/contracts`). Ex. :
  `group` de teamaccess (libre en général, `team-<team>` exigé par workspace).

**Hiérarchie des interventions (du moins cher au plus cher — on ne descend une marche
que si la précédente est impossible) :**
1. **H0 ÉLIMINER** — champ mono-valeur : défaut+masqué / dérivé. État invalide
   irreprésentable, zéro machinerie.
2. **H1 FIGER À LA COMPOSITION** — brique générique, valeur déterminée dans CE
   compound : `fix` de recette (ex. team-space fige `group=team-${spec.team}`).
3. **H2 DÉCLARER UN CONTRAT** — valeur réellement libre ET couplée à une autre brique
   du canevas : provides/requires (le Studio pré-câble et valide à la conception).
4. **H3 MACHINERIE** (dérivation auto, scan) — uniquement à l'échelle, sur déclencheur.

Audit du catalogue : `docs/AUDIT-ENCAPSULATION.md` (à refaire à chaque brique ajoutée).

## Ce qu'on NE construit PAS (over-engineering — leçons de cette itération)
- **Pas de renderer générique maison** : les variantes câblent déjà un renderer partagé Syntasso.
- **Pas de générateur « schéma → CRD » maison** : les variantes à schéma riche le font déjà (XRD/CRD/pulumi).
  Un helper maison ne se justifie **qu'à grande échelle**, si le hand-edit helm devient répétitif — **jamais préventivement**.
- **Pas de kro / kustomize pour un namespace** : kro (usine à operators : RGD → CRD + contrôleur) = overkill
  pour des ressources statiques ; kustomize n'est **pas câblé** par Kratix et **ne résout pas** les enums (outil de sortie, sans schéma).

## Le bon choix pour « Workspace » (namespace + quota + RBAC)
→ **un chart Helm** (templates namespace/quota/limitrange/rbac + `values` avec la table tier→quota),
**poussé versionné dans Harbor**, puis **`kratix init helm-promise`** (CRD + renderer câblés), **+ un
hand-edit du CRD pour les `enum`**. Officiel, scalable, **zéro renderer maison**.

## OSS vs réellement fermé chez Syntasso (sourcé)
| Capacité | Statut |
|----------|--------|
| CLI de scaffold (famille `init …-promise`), renderers partagés, Backstage push | **OSS** (vérifié source) |
| **Santé** : CR `HealthRecord` | **OSS** (`docs/main/guides/resource-health`) |
| **Approvals (cœur)** : `workflow-control.yaml` (suspend/retryAfter) | **OSS** (`docs/main/reference/workflows`) |
| SDK Python/Go, Marketplace, PromiseRelease, destinationSelectors, compound | **OSS** (vérifié) |
| Support/SLA, testing à l'échelle, base images sécurisées + supply-chain, intégrations SaaS (Jira/ServiceNow/Slack) | **fermé SKE** |
| Code des plugins UI SKE (`KratixResourceEntityPage`) | **fermé** (équivalent OSS approximé = frontend Terasky) |

**Le moteur est OSS et reproductible ; le fermé se réduit à un service (support/sécurité/SLA), des connecteurs SaaS, et du code UI — pas le cœur.**
