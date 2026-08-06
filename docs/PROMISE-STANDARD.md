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

## 9bis. Promesses ANSIBLE — ⛔ MOTEUR ABANDONNÉ (conservé pour mémoire)

> **STATUT : ABANDONNÉ le 2026-07-28** (`backstage-platform/Objectives/ansible/
> DECISION-ABANDON.md`), **retrait EN COURS depuis le 2026-08-06 (objectif CD8)**.
> **N'écrivez plus de promesse `ansible`.** Le remplacement est le **§9quater** :
> une automatisation AWX s'expose en **ACTION** (`spec.type: awx-action`), dont le
> formulaire se dérive du **survey** — le contrat déclaré dans un système tiers.
>
> **La raison, à ne pas re-litiger** : *« le guichet peut être unique, la GARANTIE
> ne peut pas l'être »* — une entrée du catalogue qui signifie « un job a rendu 0 »
> ne peut pas voisiner avec des entrées qui signifient « la plateforme connaît
> l'état et l'y ramène ». Trois défauts mesurés l'ont confirmé : un verrou de cible
> qui n'existait sur AUCUN produit livré, une santé qui ne sait pas mourir, et une
> cadence de 120 s (262 800 exécutions/an/demande) dont le coût a **gelé les
> kubelets du cluster dans la nuit du 2026-08-06** — c'est ce qui a déclenché CD8.
>
> **État du retrait** : les 2 promesses TÉMOINS retirées (2026-08-06) · les 2
> produits RÉELS (`service-legacy`, `service-account`) conservés et ralentis à 24 h
> **jusqu'à leur migration en `awx-action`** (on ne retire pas une capacité
> demandée sans l'avoir remplacée) · le slot `ansible` du contrat, du form-switch
> et du Studio reste ouvert jusque-là — le retirer avant invaliderait leurs claims
> et **gèlerait l'application de TOUTES les demandes**.
>
> Ce qui suit décrit le moteur tel qu'il a été construit : c'est de l'histoire, pas
> une recommandation.

Les quatre autres moteurs visent des objets dotés d'une API déclarative. Dans une
banque, c'est la **minorité** du parc : VM, middleware, bases sur VM, appliances,
réseau, Windows, legacy. Ces cibles ont un SSH ou une API, mais **aucun contrôleur
qui converge**. Le moteur `ansible` fait passer le contrat de self-service de
l'autre côté de cette frontière.

**Le client possède déjà AWX / AAP.** On ne lui vend pas un outil de plus : on donne
un portail, une gouvernance et une piste d'audit à ce qu'il fait déjà.

### Le modèle : authoring dédié → forme opérateur → runtime operator

```
rôle Ansible + meta/argument_specs.yml + job template AAP
        ↓  kratix new-ansible-promise
CRD dérivée + watches.yaml + Deployment (runtime PARTAGÉ) + RBAC
        ↓  délégation à kratix new-operator-promise --src (moteur 4, inchangé)
promesse → claim → CR → l'opérateur réconcilie → AWX exécute → conditions de statut
```

La séparation est entre ce que l'auteur **déclare** et ce qui **tourne**. Ce qui
tourne est intégralement le chemin operator déjà prouvé — renderer
`from-api-to-operator`, CR nommé d'après le claim, fiche, graphe, onglet live,
santé. Ce qui est neuf, c'est uniquement la **fabrication** de la promesse.

### Ce que l'auteur fournit — et rien d'autre

| Il écrit | Il n'écrit PAS |
|---|---|
| un rôle avec `meta/argument_specs.yml` | la CRD (elle se dérive) |
| le nom du job template AAP autorisé | un opérateur |
| la cible autorisée (inventaire, ou liste de groupes) | une image, un Dockerfile |
| le Secret du jeton AWX de SON équipe | le RBAC, le watches, le Deployment |

`meta/argument_specs.yml` est le mécanisme **natif** d'Ansible : il valide déjà le
rôle à l'exécution. Le dériver supprime la double écriture — exactement ce que
`values.schema.json` a fait pour helm. **Un rôle sans spécification d'arguments
n'est pas dérivable** ; le message d'erreur donne l'exemple minimal à écrire.

⚠️ Les noms de variables du rôle et ceux du **sondage du job template** doivent être
les mêmes. AWX exige **toutes** les variables requises d'un sondage, *même celles qui
ont une valeur par défaut* : un champ inventé côté CRD rend le produit inutilisable —
et, pire, **indestructible** (son finalizer échoue en boucle). C'est précisément la
raison d'être de la dérivation.

### Le runtime est PARTAGÉ — aucune image par produit

L'image du contrôleur est celle, **publique et épinglée par empreinte**,
d'operator-sdk ; les trois rôles génériques (`awx-contrat`, `awx-runner`,
`awx-remover`) et leurs deux enveloppes sont montés depuis **une ConfigMap de
plateforme** (`ansible-operator-roles`). Par produit il ne reste qu'une CRD, un
`watches.yaml`, un Deployment et du RBAC. Le levier « zéro image par promesse » est
donc préservé — et même dépassé : il n'y a **aucune** image à construire.

⚠️ Fait vérifié : l'image d'operator-sdk n'embarque **aucune collection Ansible**
(ni `kubernetes.core`, ni `operator_sdk.util`). Les rôles n'utilisent donc que
`ansible.builtin` et parlent à l'API Kubernetes avec le jeton de compte de service
du pod. C'est ce qui permet de les monter au lieu de les cuire dans une image.

### L'autorisation : le job template ET la cible se déclarent

Avec un jeton AWX, un opérateur pourrait lancer **n'importe quelle** automatisation,
y compris celle d'une autre équipe. Deux verrous ferment cela :

1. **À la conception** — le job template autorisé et la cible vivent dans
   l'**environnement du contrôleur**, posé par le Deployment du produit. Ils sont
   donc hors de portée du `spec` d'une demande. Une demande qui porte une clé
   réservée (`jobTemplate`, `inventory`, `limit`, `extraVars`…) est **refusée** avec
   un motif lisible, **avant** tout lancement.
2. **À l'exécution** — chaque fournisseur a **son** utilisateur AWX, dont le seul
   droit est d'exécuter **son** job template. Un lancement croisé renvoie **403**.

La cible obéit à la même règle : verrouiller le playbook sans verrouiller la machine
ne verrouille rien. Le produit **fixe** sa cible (un inventaire), ou **ouvre le
choix dans une liste déclarée** de groupes d'hôtes. **Jamais un nom d'hôte libre
laissé au demandeur.**

### La frontière avec AAP

La plateforme ne détient qu'**un jeton d'API par fournisseur**. Les **inventaires**
et les **credentials machine (SSH)** restent chez AWX/AAP. L'opérateur désigne une
cible **par son nom** ; il ne porte jamais un accès à une machine.

### Le dé-provisionnement se déclare, sinon rien ne démarre

Un produit doit dire comment il se retire : soit un **job template de
décommissionnement** (`jobTemplateDelete`), soit la **variable d'état** du job
template nominal (`stateVar`, rejouée à « absent »). Sans l'un des deux, le
contrôleur **refuse de démarrer** — plutôt qu'une suppression qui ne ferait rien
sur la machine. Si le retrait échoue, le finalizer n'est pas relâché : la ressource
ne disparaît pas, et personne ne croit à une suppression propre.

### Les limites — sans les adoucir

- **Le graphe et l'onglet live montrent le CR SEUL.** La machine n'est pas un objet
  Kubernetes ; c'est la fiche du CR qui la représente. Limite structurelle, partagée
  avec le moteur operator.
- **Un produit = un Deployment d'opérateur.** L'image et les rôles sont partagés, mais
  il y a un pod par produit : ≈ **100–130 Mio** mesurés au repos, réservation déclarée
  50 m / 128 Mio. Le passage à l'échelle se tranche sur ce chiffre, pas sur une intuition.
- **Un rôle sans `meta/argument_specs.yml` n'est pas dérivable.** Charge assumée pour
  l'auteur, la même que `values.schema.json` côté helm.
- **Les validations croisées d'Ansible** (`mutually_exclusive`, `required_together`…)
  ne s'expriment pas dans une CRD : elles sont signalées à la dérivation et restent
  vérifiées par le rôle **à l'exécution**, pas par le formulaire.
- **L'exécution dépend d'AAP.** Si AAP est indisponible, la réconciliation **échoue** —
  condition `Failure` sur le CR et `healthStatus: unhealthy` sur la demande. C'est
  visible, ce n'est jamais silencieux.
- **⚠️ La lignée CONSOMMATEUR ne se pose pas toute seule.** La lignée *provider* tient
  (la promesse porte `platform.kratix.io/provider`). Mais la fiche d'une instance n'est
  ownée par la squad demandeuse que si le contrat expose un champ `team` : c'est la
  condition qui accroche `RequesterTeamPicker` au formulaire
  (`backstage-component/scripts/scaffolder.py`), et la première branche de la chaîne
  d'owner (`catalog.py`). Or le contrat d'un produit ansible est **dérivé de
  `meta/argument_specs.yml`**, où un rôle n'a aucune raison de déclarer `team` — la
  fiche retombe alors sur `team-platform`. **Contournement** : poser le label
  `platform.example.io/component-of-owner: <squad>` sur la demande (2ᵉ branche de la
  chaîne). **Cure**, deux lignes, au backlog : le plugin ajoute `team` au contrat
  dérivé, et `awx-runner` l'exclut des variables du job — exactement comme il exclut
  déjà `target`. Sans cette exclusion, `team` partirait dans le sondage AWX et le job
  serait **refusé** (leçon d'AN3 : le contrat du produit EST le contrat du sondage).
- **La santé ne remonte PAS par l'agent AD3** : son parcours en profondeur ne descend
  que dans les groupes `platform.example.io`, or l'opérande d'un produit ansible vit
  dans un groupe tiers. C'est **le runtime lui-même** qui publie son `HealthRecord`,
  mécanisme natif de Kratix dont l'agent n'est qu'un producteur parmi d'autres. Pour
  un produit dont la vérité est sur une machine et non dans un objet Kubernetes,
  c'est la bonne réponse.

### La cascade — dans l'ORDRE, par GitOps

⚠️ **Règle d'or déjà payée sur ce projet** : supprimer une promesse alors que des
claims vivent encore **gèle la suppression** (le finalizer supprime les
`PromiseRevision` avant que les claims aient fini → boucle infinie). **Toujours :
les demandes d'abord, on attend, la promesse ensuite.** Le remède — révision de
secours + réveil des claims par annotation — est décrit dans le gotcha
« DEADLOCK à la suppression d'une promesse » ; le citer, pas le réinventer.

Retirer une promesse ansible retire **son** opérateur, **sa** CRD et **son**
watches. Cela ne touche ni le runtime partagé (ConfigMap de plateforme) ni AWX :
le job template, l'inventaire et les identifiants machine restent chez le client.

## 9ter. Promesses TERRAFORM NATIF (moteur 6 — le module EST le contrat)

> Prouvé bout en bout par le set TN1→TN8 (`backstage-platform/Objectives/terraform-native/`).
> ⚠️ **Deux voies terraform coexistent** : celle-ci, et la voie Crossplane
> (`provider-terraform`, en production depuis 2026-07-07). Le choix est documenté dans
> `VERDICT-COMPARATIF.md` — il se décide sur **qui écrit** : si le fournisseur écrit du
> Terraform, cette voie-ci ; s'il compose avec d'autres ressources Kubernetes, la voie
> Crossplane.

**Ce que l'auteur écrit** : son module, tel quel. Ni CRD, ni Composition, ni image.

**Le contrat se DÉRIVE des blocs `variable`** (mécanisme natif Terraform) :

| dans le module | dans le formulaire |
|---|---|
| pas de `default` | champ **requis** |
| `validation` avec `contains([…])` | **liste de choix** |
| `validation` avec `can(regex(…))` | **motif** |
| `validation` avec `length(…) <= N` | longueur maximale |
| `description` | le texte sous le champ |
| `output` avec `sensitive` | **exclu du sélecteur**, jamais du Secret |

⚠️ `number` et **non** `integer` : Terraform n'a pas de type entier. Prétendre le contraire
ferait un formulaire plus strict que le module.

⚠️ Une `validation` intraduisible est **SIGNALÉE, jamais bloquante**. Refuser pousserait
l'auteur à retirer ses validations pour plaire à notre outil — l'inverse du but. Terraform
continue de les appliquer.

**Ce que le produit DÉCLARE** (bloc `spec.terraform` du PromiseRequest) :

- `approval` : **`auto` (surveillée) OU `manuelle` (approuvée) — pas les deux.** Mesuré :
  avec un plan approuvé nommément, l'exécuteur **détecte** la dérive mais ne la corrige
  jamais, et n'offre **aucun plan à approuver** pour elle. Une offre choisit, et le dit.
- `interval` : ⚠️ **chaque tour fait naître un POD**. À 2 minutes, 720 pods par jour et par
  demande — le chiffre exact qui a condamné la cadence du moteur ansible. Défaut : **1 h**.
- `credsSecret` : les identifiants du provider, lus en **variables d'environnement** par le
  runner. **Jamais** en variables terraform : une variable atterrit dans l'**état** ET dans
  le **plan**, et `sensitive` masque l'affichage, pas le stockage.

**Ce que la PLATEFORME décide, et que le module ignore** :

- **le chiffrement de l'état** (`TF_ENCRYPTION` par l'environnement du runner). L'état
  contient les valeurs réelles, y compris les sorties `sensitive`. Non optionnel en banque.
- **la source du module est une DÉPENDANCE de la promesse** — appliquée une fois par
  Destination, pas clonée par demande.

### Les limites, sans adoucissement

- **maturité** : `tofu-controller` est en **v0.16.4, toujours 0.x**, petite équipe.
  Apache-2.0 donc forkable, mais c'est le risque à porter en comité.
- **deux contrôleurs de plus** : `tofu-controller` et le `source-controller` de Flux.
  ⚠️ Installer le second **n'est pas « faire tourner Flux »** — c'est un contrôleur dont le
  seul métier est d'aller chercher un artefact, comme cert-manager pour Kratix. **ArgoCD
  reste le seul moteur GitOps.**
- ⚠️ le RBAC vendorisé de l'amont accorde **`cluster-admin`** au compte de service du
  contrôleur. Vendorisé tel quel, documenté, **à trancher**.
- ⚠️ **les références inter-namespace sont désactivées par défaut** — c'est une vraie
  frontière entre équipes. La source vit **avec les demandes**, on ne l'affaiblit pas.
- ⚠️ **un compte de service `tf-runner` par namespace** accueillant des demandes. Sans lui
  la panne est **silencieuse** : la ressource reste en `Progressing`, elle ne tombe jamais
  en erreur.
- ⚠️ `destroyResourcesOnDeletion` vaut **`false` par défaut**. Sans cette ligne, supprimer
  une demande **ne détruit rien**. La promesse la pose ; ne jamais la laisser au défaut.
- ⚠️ le **secret d'état survit** à la destruction (vide, sans rien de sensible — mais un par
  demande supprimée). À balayer.
- ⚠️ le format OCI de **Flux** (`flux push artifact`) **n'est pas** la source de module
  `oci://` native d'OpenTofu. Les deux marchent avec Harbor, ce ne sont pas les mêmes paquets.

### Suppression — l'ordre compte

**demandes → promesse → exécuteur.** Prouvé en TN8 : la promesse retirée, sa dépendance est
prunée et l'exécuteur reste intact ; `git revert` restaure tout.

⚠️ Et au niveau d'une ressource : **supprimer la SOURCE avant la ressource BLOQUE le
finalizer** — il lui faut le module pour jouer le destroy. Remède : recréer la source.

## 9quater. Le contrat DÉCLARÉ — promesses `script` et actions (moteur 7)

> **Statut : standard écrit AVANT le code (set CD, 2026-08-06)** — comme le contrat des
> niveaux l'a été avant l'adoption. L'implémentation = objectifs CD2→CD5 ; chaque garantie
> ci-dessous a son test de falsification dans la table §7 d'ADOPTION-STANDARD. Rien de ce §
> n'est promis à un demandeur tant que la preuve correspondante n'est pas jouée.

**Le cas** : un exécutable réel — script shell, appel d'API sans spec, procédure stockée —
dont le contrat ne vit **nulle part**. Aucune dérivation possible ; l'inférence (deviner
depuis `--help`, des exemples) est écartée : un contrat deviné est pire qu'un déclaré.
**Le principe** : *là où le contrat ne peut pas être LU, il est DÉCLARÉ — une fois,
co-localisé avec l'artefact — et tout l'aval dérive de la déclaration comme s'il l'avait
lue.* (C'est ce que font les mieux placés ailleurs : KubeVela et kro déclarent co-localisé
et dérivent ; Syntasso écrit l'API à la main — notre plancher ; Backstage/Port déclarent
côté portail — la déclaration y pourrit loin du code, d'où la co-localisation.)

### La convention `contract.schema.json`

- **JSON Schema plat autoportant, LE MÊME dialecte que `values.schema.json`** (celui que
  `schema-to-crd.py` consomme : bornes, patterns, enums, `x-kubernetes-*` pour le CEL,
  `x-kratix-internal` pour les knobs) → la chaîne aval est INCHANGÉE.
- Co-localisé avec l'exécutable dans le dépôt git, **pinné par tag** (le pin de
  gouvernance, comme un module terraform).
- Précédence : **fichier source > `spec.api` inline du claim** (règle CT5) — le Studio
  sait composer la déclaration (« le stylo », l'ApiEditor) quand le fichier manque ; si
  le fichier apparaît ensuite, IL gagne.

### Les verbes sont des FICHIERS — la classe suit les verbes, jamais le marketing

La présence déclare, structurellement — un dossier ne peut pas mentir sur ce qu'il
contient :

| Fichiers présents | Classe | La phrase de carte (GELÉE — reprise telle quelle à l'écran) |
|---|---|---|
| `run.sh` seul | **ACTION** | « Une exécution qui se termine — ne surveille rien, ne répare rien ; supprimer la demande ne défait rien. » |
| `apply.sh` + `destroy.sh` | **RESSOURCE** | « Converge au changement déclaré · destruction pilotée · pas d'auto-guérison. » |
| + `observe.sh` (optionnel) | ouvre la dérive | **Étage 2, GATÉ** — sa présence est SIGNALÉE, jamais câblée ni promise en v1. |

- `run.sh` **XOR** (`apply.sh` + `destroy.sh`) : le mélange est REFUSÉ à la génération,
  fichiers trouvés et attendus nommés dans le refus.
- *« Le guichet peut être unique, la GARANTIE ne peut pas l'être »* (décision d'abandon
  Ansible) — ici la garantie est portée par la STRUCTURE : `run.sh` seul ne peut pas
  devenir une ressource, `apply`+`destroy` ne peuvent pas se présenter en action.
- Sans `observe.sh`, **aucune surface de dérive n'existe** sur la fiche — ni « alignée »
  ni « je ne sais pas » (règle CL12 : encadrer une surface qu'on n'observe pas lui
  donnerait un statut qu'elle n'a pas).
- Une ACTION n'apparaît **JAMAIS dans la console de suivi** — elle ne possède rien à
  suivre (cadrage §3.2 : la console suit des ressources — santé, cycle de vie) ; son
  résultat vit sur sa fiche, et pour AWX dans le journal du job.
- `apply.sh` doit être **IDEMPOTENT** (re-run sans changement = zéro effet) — c'est SA
  moitié du contrat ; celle de la plateforme est de ne le rejouer qu'au changement
  déclaré.

### Le contrat d'exécution du runner (ce que le script peut supposer)

- Chaque champ du contrat arrive en variable **`SPEC_<CHAMP>`** (majuscules).
- Les identifiants du système cible arrivent par l'ENVIRONNEMENT (`credsSecret` déclaré
  par la promesse, monté par la plateforme) — **jamais en argument** (un argument finit
  dans les journaux).
- Les sorties à publier s'écrivent en `clé=valeur` dans le fichier pointé par
  **`$SORTIES`** ; le runner les porte au `status` du claim.
- **Un code de sortie ≠ 0 est un échec de la demande, VISIBLE** — jamais un succès qui
  ment.
- Le runner est une image **PARTAGÉE, digest-pinnée** (jamais une image par produit — le
  levier de la plateforme) : elle clone la source à la ref pinnée et exécute le verbe.
  ⚠️ Limite dite : un script qui exige un outil absent de l'image partagée n'est pas
  couvert en v1 (l'image par-source déclarée = extension gatée).

### La frontière de sécurité — trois verrous

1. Une promesse `script` ne déclare **JAMAIS** de `Permissions` Kratix : aucun droit
   cluster n'est accordé au pipeline.
2. L'image runner n'embarque **PAS kubectl**.
3. Le périmètre est **l'EXTÉRIEUR du cluster** (les systèmes cibles) — ce qui vit DANS le
   cluster a déjà quatre moteurs. Écrit sur l'offre.

### La gouvernance — rien de spécifique, par construction

Demande = PR sur portal-templates → portier iTop → merge humain. Actions comprises.
⚠️ Fait Kratix à dire sur la carte d'une ACTION : **modifier la demande ré-exécute le
geste** (le pipeline re-tourne au changement de spec).

### Les actions AWX — le même moteur, le contrat déclaré AILLEURS

Un **survey AWX** est un contrat déclaré dans un système tiers lisible par API : une
action AWX est une promesse ACTION dont le `run` — fourni par la plateforme — lance LE job
template déclaré et attend sa fin (`status` = résultat + URL du journal AWX).
`spec.type: awx-action` réutilise le bloc `automation` existant et ses CEL (jobTemplate
UNIQUE · cible déclarée `inventory` XOR `allowedLimits` · `awxTokenSecret` par
fournisseur — un jeton déclaré GAGNE toujours sur le jeton de lancement par défaut de la
plateforme). Le formulaire vient du survey — écrit une fois, chez le client ; un champ
`password` de survey est **EXCLU** (un secret n'entre jamais dans un claim git).
Ceci EXÉCUTE la Partie 3 de `DECISION-ABANDON.md` (le cadrage AWX-comme-actions) : les
actions remplacent l'usage du moteur ansible §9bis, le moteur réconciliant reste
abandonné.

### Slugs figés

`script` · `awx-action` · `run` / `apply` / `destroy` / `observe` ·
`contract.schema.json` · `SPEC_<CHAMP>` · `SORTIES`.

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
