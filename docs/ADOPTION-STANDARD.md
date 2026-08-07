# ADOPTION-STANDARD — le contrat des niveaux d'adoption du legacy

Statut : v1, 2026-07-30 (LG1). Canonique — toute surface (Studio, Marketplace, Console) et tout
moteur qui affiche ou applique un niveau d'adoption se réfère À CE document. Amendable par PR ;
le vocabulaire affiché reste soumis à validation utilisateur finale.

Héritage : ce contrat reprend et généralise le « lifecycle contract » de l'ancien modèle
(`platform-control/docs/dependency-track-adoption-architecture.md`), dont trois principes sont
conservés tels quels : **l'adoption n'est pas une prise de propriété immédiate** ; **aucun objet
d'identité n'est créé tant que le niveau ne l'exige pas** ; **la remédiation fine par contrôle**
(backlog du niveau Géré, non couverte en v1).

---

## 1. Vocabulaire

| Slug (donnée, stable) | Libellé affiché (FR) | Une phrase de garantie (à reprendre TELLE QUELLE dans les tooltips) |
|---|---|---|
| `repertorie` | **Répertorié** | « La plateforme sait que ça existe, et à qui c'est. Elle n'y touche pas et n'en promet rien d'autre. » |
| `observe` | **Observé** | « La plateforme voit l'état réel et la dérive ; elle ne modifie rien, par construction. » |
| `gouverne` | **Gouverné** | « Rien ne change sans passer par la porte d'approbation ; l'écart au contrat est visible. » |
| `gere` | **Géré** | « La plateforme est la source de vérité : elle détecte la dérive et y ramène l'état. » |

- Donnée portée par : le champ **`mode`** du claim (niveaux 1-3, enum `observe|gouverne|gere`,
  défaut `gere` = rétro-compatible) et l'annotation **`platform.kratix.io/adoption-niveau`**
  sur les fiches catalogue (les 4 niveaux, `repertorie` étant posé par les connecteurs).
- ⚠️ Ne PAS recycler `platform.kratix.io/maturity` (concept de maturité d'OFFRE, distinct).

## 2. Le contrat par niveau

### Niveau 0 — Répertorié (catalogue seul, AUCUN claim)

- **Permis** : lister depuis une SOURCE (API GitHub/Harbor, CMDB…), projeter une entité catalogue
  (nom QUALIFIÉ par source, owner mappé ou bac « orphelins »), poser `adoption-niveau: repertorie`.
- **Interdit** : tout appel d'écriture vers la source ; toute promesse de santé, de conformité ou
  de cycle de vie ; tout moteur.
- **Sorties attendues** : l'entité, son owner (ou `orphelins`), l'horodatage de synchro.
- **Coût** : ~zéro par ressource (un connecteur PAR SOURCE, jamais par ressource).
- **Falsification** : (i) l'identité employée par le connecteur est en lecture seule vérifiable ;
  (ii) couper le connecteur ⇒ l'horodatage de synchro vieillit VISIBLEMENT (jamais un parc figé
  qui a l'air frais).

### Niveau 1 — Observé (un claim se LIE, le moteur lit)

- **Permis** : lier par identifiant une ressource existante ; lire son état réel ; produire et
  stocker le DIFF déclaration↔réel ; remonter statut et santé ; signaler la dérive.
- **Interdit** : TOUTE écriture vers la ressource (par construction, pas par convention) ; toute
  création d'objet annexe à effet de bord (identité, accès) ; toute destruction, y compris à la
  suppression du claim.
- **Sorties attendues** : conditions du moteur, le plan/diff lisible, l'horodatage du dernier
  tour, `adoption-niveau: observe` sur la fiche.
- **Suppression du claim** = PUR OUBLI : la ressource est intacte ; les artefacts de liaison
  (état) deviennent orphelins et sont balayés (backlog balayage — jamais détruits AVEC la
  ressource).
- **Coût (corrigé par le pilote LG2)** : **ZÉRO pod au repos** — le moteur produit le diff à la
  LIAISON puis se gare (« stopped to wait for manual operations », constaté) ; un pod naît par
  RE-VÉRIFICATION demandée, pas par intervalle. L'Observé est un GESTE de lecture, pas un régime.
- **Re-vérification** : à la demande (le bouton « Re-vérifier » des surfaces) = le geste
  `tfctl replan` — patch du sous-ressource status (vider `plan.pending` + les révisions) puis
  `reconcile.fluxcd.io/requestedAt`. ⚠️ `requestedAt` SEUL ne réveille pas un objet garé.
  La dérive CONTINUE n'est PAS une promesse de l'Observé — elle commence avec la gestion
  (post-premier-apply) ; l'Observé promet « l'écart est montrable à tout moment, sur demande ».
- **Falsification** : chaque plan produit sans AUCUNE mutation côté fournisseur (audit API) ;
  ressource modifiée à la main ⇒ la re-vérification MONTRE l'écart, rien n'est réappliqué.

### Niveau 2 — Gouverné (rien ne change sans la porte)

- **Permis** : tout l'Observé ; PLUS : préparer un changement (plan) qui ATTEND une approbation ;
  appliquer UNIQUEMENT un plan approuvé ; évaluer l'écart à un profil de conformité (v1 : le
  diff du plan EST l'évaluation ; profils nommés = backlog).
- **Interdit** : appliquer sans approbation (le défaut est fermé) ; **CONVERGER SANS
  DÉCLENCHEMENT HUMAIN** — la règle du Gouverné (décision utilisateur, 2026-07-30) : la
  dérive n'est JAMAIS corrigée seule, la corriger est un geste humain dédié ; détruire
  (même à la suppression du claim) ; escalader des droits non déclarés.
- **Exigence de visibilité** : la dérive APPARAÎT DANS LA CONSOLE (« dérive détectée »),
  jamais seulement dans un outil d'infrastructure — c'est l'essentiel du niveau.
- **Sorties attendues** : le plan lisible cité dans la demande d'approbation ; l'état
  « en attente d'approbation — ‹réf ticket› » ; l'empreinte couverte par l'approbation.
- **Suppression du claim** = pur oubli (comme Observé).
- **Falsification** : une tentative d'application SANS approbation échoue et ça se VOIT (statut
  rouge/bloqué, jamais un contournement silencieux) ; un contenu modifié APRÈS approbation
  redevient bloqué (l'empreinte, pas le temps, fait foi).
- **Porte** : l'approbation passe par le portier ITSM existant (approbation liée à l'EMPREINTE de
  la demande — jamais au seul identifiant de plan, qui n'encode que la source).

### Niveau 3 — Géré (source de vérité)

- **Permis** : réconciliation complète, correction automatique de la dérive, cycle de vie total ;
  la destruction à la suppression du claim SI l'offre le déclare (défaut du greenfield actuel).
- **Interdit** : rien de plus que le contrat de l'offre ; la remédiation PAR CONTRÔLE
  (n'appliquer qu'une liste de contrôles autorisés) reste un backlog explicitement nommé.
- **Sorties attendues** : celles du produit greenfield (statut, santé, sorties étiquetées).
- **Falsification** : dérive provoquée ⇒ corrigée SEULE dans l'intervalle (le contraste exact de
  l'Observé — les deux preuves se répondent).

## 3. Transitions

| De → Vers | Autorisée ? | Geste | Garde |
|---|---|---|---|
| Répertorié → Observé | oui | « Adopter » : un claim naît, PRÉ-REMPLI depuis l'entité répertoriée | admission du claim (PR) |
| Observé → Gouverné | oui | PR d'une ligne (`mode`) | portier ITSM (empreinte) |
| Gouverné → Géré | oui | PR d'une ligne | portier ITSM ; le PREMIER apply est le moment de vérité : plan cité, approuvé, puis plan VIDE |
| Géré → Gouverné / Observé | oui (rétrogradation) | PR d'une ligne | l'état est CONSERVÉ ; plus aucune écriture ; JAMAIS de destruction en descendant |
| tout niveau → suppression du claim | oui | suppression de la demande | Observé/Gouverné : pur oubli. Géré : le contrat de l'offre s'applique (destruction si déclarée) — ⚠️ sauf ADOPTÉ : oubli même en Géré, v1 (ceinture ci-dessous) |
| Répertorié → rien | oui | l'entité disparaît quand la source ne la liste plus (full-mutation) | — |

Règles transverses : une transition ne saute jamais la porte quand elle ÉLARGIT les droits
(monter = approuver) ; descendre est libre d'approbation mais tracé (PR) ; l'affichage ne
PRÉCÈDE jamais la mécanique (un badge dit ce qui est, pas ce qui est demandé).

⚠️ **Le geste de bascule (helm/operator/compound) — CONSTATÉ AU2** : Kratix ne re-place
JAMAIS un workloadGroup déjà placé — ni quand les labels d'une Destination changent (pas
même un label `misscheduled`), ni quand le selector du work change (un changement de
`mode`). Le contenu du placement est mis à jour, sa CIBLE jamais. Toute transition qui
change le chemin (promotion/rétrogradation) inclut donc la suppression du workplacement
périmé → le scheduler re-place selon le selector courant (<30 s, constaté dans les deux
sens). Un geste PLATEFORME, automatisé côté portail (AU6) — jamais demandé à l'humain,
même famille que le « Re-vérifier » (patch d'objet interne, jamais la ressource).

### 3 bis. La non-destruction d'un adopté — LA GARANTIE, PUIS SES PORTEURS

⚠️ **LA GARANTIE (elle ne dépend d'aucun moteur) : supprimer le claim d'une ressource
ADOPTÉE ne la détruit pas — à TOUS les niveaux, y compris Géré (v1).** « Adoption ≠
propriété immédiate » : ce que la plateforme n'a pas créé, elle ne le détruit pas en
partant. Détruire volontairement un adopté est un geste explicite, hors v1 (backlog).
Est ADOPTÉE toute ressource dont la **liaison est renseignée**, ou dont le mode ≠ `gere`,
ou qui porte le marqueur durable du parcours (un adopté promu en Géré RESTE un adopté).

⚠️⚠️ **CETTE GARANTIE A UN PORTEUR DIFFÉRENT PAR MOTEUR, ET LE CRITÈRE N'EST PAS LE
ROUTAGE — C'EST CE QUE LE MOTEUR REND.** Deux cas, et un seul les sépare :

| moteur | l'objet rendu est… | porteur de la non-destruction |
|---|---|---|
| **helm** | **la ressource elle-même** (Namespace, Quota, RoleBinding…) | **ceinture** `argocd.argoproj.io/sync-options: Prune=false,Delete=false` sur les objets rendus |
| **operator** | un CR dont la suppression détruit, et une CRD **tierce** n'offre aucun levier | **ceinture** sur le CR |
| **compound** | rien en propre | **délègue** : chaque enfant applique SON porteur |
| **crossplane** | l'**ENTRÉE** d'un contrôleur (un XR, qui porte un finalizer) | **`managementPolicies` sans `Delete`** sur la ressource managée (table AU4) |
| **terraform** | l'**ENTRÉE** d'un contrôleur (un objet `Terraform`, finalizer `finalizers.tf.contrib.fluxcd.io`) | **`destroyResourcesOnDeletion: false`** sur l'objet `Terraform` |
| **script / awx** | **rien dans le cluster** — le réel vit à l'EXTÉRIEUR (base, compte, geste sur un système cible) | **moteur** : le runner SAUTE `destroy` si `est_adopte` (mode ≠ `gere` OU marqueur durable `status.adopte`) ✅ CD9 phase B |
| **api** | rien en propre — la désignation produit un objet `Terraform` (ressource) ou une promesse `script` (action) | **hérité** : `destroyResourcesOnDeletion: false` pour une ressource ; une ACTION n'a rien à ne pas détruire |
| répertorié | rien n'est rendu | sans objet |

**LA RÈGLE, en une phrase** : *si le moteur offre un levier de non-destruction, on
l'utilise ; sinon on protège l'objet rendu avec la ceinture.*

⚠️ **NE PAS mettre la ceinture sur l'ENTRÉE d'un contrôleur.** Un XR ou un objet
`Terraform` que le prune ne peut plus retirer devient un **ORPHELIN VIVANT** : il garde
son finalizer et continue de réconcilier (terraform replanifierait toutes les 5 min)
pour une demande qui n'existe plus. La ceinture protège une RESSOURCE, jamais une
INSTRUCTION.

**Pourquoi la ceinture, là où elle s'applique** : un changement de mode fait CHANGER les
fichiers de chemin — la rétrogradation Géré→Observé fait QUITTER l'application
`prune: true`, qui DÉTRUIRAIT les objets sans elle. **PROUVÉ EMPIRIQUEMENT (AU2)** : la
rétrogradation d'un témoin SANS ceinture a rendu `ConfigMap … pruned` — la destruction
constatée sur un objet inoffensif, pas supposée.

🚨 **LEÇON DE CONCEPTION, PAYÉE DEUX FOIS.** Cette garantie et celle de l'adoptabilité
(« cette offre est adoptable ») avaient toutes deux été implémentées **à l'intérieur du
chemin de routage Kubernetes** — comme si le routage était le porteur universel de
l'adoption. Il ne l'est pas : c'est un mécanisme parmi trois. Conséquences constatées le
2026-07-31 : la fabrique ne pouvait STRUCTURELLEMENT pas marquer adoptable une offre
terraform (CL4), et la ceinture n'était jamais posée pour un moteur sans routage — de
sorte que **le moteur sur lequel tout ce standard a été prouvé (terraform : LG2, LG3,
CL3) était le seul à ne recevoir aucune des deux garanties**, en silence.
**La forme correcte est celle de §4 : énoncer la garantie, puis publier sa déclinaison —
et faire lire cette déclinaison au code comme une DONNÉE, jamais l'inférer d'un
mécanisme voisin.** Le porteur est déclaré par l'annotation
`platform.kratix.io/adoption-non-destruction` (`ceinture` | `moteur`), posée par le
plugin qui connaît son moteur.

## 4. Déclinaison par moteur

> **LE PRINCIPE (AU1)** : le niveau d'adoption ne se joue jamais dans le moteur — il se règle
> dans **la DERNIÈRE couche avant la ressource réelle**, celle qui écrit dans le monde.
> ArgoCD livre partout, mais il n'est cette dernière couche QUE pour helm (les manifestes
> SONT la ressource) ; pour les autres, il ne livre qu'une INTENTION (XR, CR, objet
> Terraform) qu'un exécuteur traduit ensuite — et c'est LUI qui porte les réglages :
>
> | Moteur | ArgoCD y livre… | La dernière couche | Les réglages du niveau |
> |---|---|---|---|
> | helm | la ressource elle-même | **ArgoCD** | la politique de sync de l'Application |
> | operator | le CR (l'intention) | ArgoCD pour le CR ; l'opérateur pour ses enfants | syncPolicy (CR) — l'opérateur maintient ses enfants conformes au CR approuvé |
> | crossplane | le XR (l'intention) | **le provider** | `managementPolicies` / `deletionPolicy` / `external-name` |
> | terraform | l'objet Terraform (l'intention) | **tofu-controller** | `planOnly` / `approvePlan` / `destroyResourcesOnDeletion` |
>
> Corollaire : le DIFF d'ArgoCD compare git ↔ cluster — il ne voit le monde réel QUE pour
> helm. L'écart réel d'un adopté crossplane se lit dans `atProvider` (le provider), celui
> d'un terraform dans le plan (tofu). Preuve interne du levier :
> `bootstrap/apps/kratix-destination.yaml:19` (`automated{selfHeal,prune}`) — tout ce que
> rendent helm/operator/compound est aujourd'hui forcé en Géré par CE seul réglage.

### La règle du Gouverné (DÉCISION UTILISATEUR, gravée le 2026-07-30)

**« RIEN NE CONVERGE SANS DÉCLENCHEMENT HUMAIN. »** Une seule définition, pas de variantes :

- un **changement** converge parce qu'un humain a mergé une PR approuvée (le merge EST le
  déclenchement — gaté par le portier ITSM, le mode et le spec sont dans l'empreinte) ;
- une **dérive** n'est JAMAIS corrigée seule — la corriger est un geste humain dédié
  (sync manuel ; futur bouton « Corriger la dérive », jumeau du « Re-vérifier ») ;
- la dérive est **VISIBLE DANS LA CONSOLE** — l'exigence de premier rang du niveau.

⚠️ **Périmètre du re-apply (constaté AU2, dit franchement)** : `automated` sans selfHeal
resynchronise à CHAQUE nouveau commit sur le chemin — le prochain merge (d'un objet A)
réapplique le chemin ENTIER et corrige au passage la dérive d'un objet B du même chemin.
La chaîne causale remonte toujours à un geste humain (la règle est tenue) ; mais le
périmètre du geste est LE CHEMIN, pas l'objet mergé. En fenêtre calme (aucun commit), la
dérive tient indéfiniment et reste OutOfSync — prouvé.

Conséquences par moteur, dites franchement :

| Moteur | Le Gouverné sous cette règle |
|---|---|
| terraform | NATIF : `approvePlan` attend, la dérive est détectée et jamais corrigée (prouvé LG3). |
| helm | app `automated: {selfHeal: false, prune: false}` : seul un merge approuvé s'applique ; la dérive reste OutOfSync, visible, non corrigée. |
| operator | idem pour le CR ; ⚠️ nuance AFFICHÉE : l'opérateur maintient ses ENFANTS conformes au CR approuvé — l'exécution d'une intention déjà approuvée, pas une convergence nouvelle. |
| crossplane | **NON OFFERT (limite dite)** : le provider converge seul par construction (`Update` ne distingue pas « appliquer un changement » de « corriger une dérive »). L'échelle crossplane = Répertorié → Observé → Géré, la PROMOTION restant gatée par un humain — et même en Géré, tout changement passe par une PR gatée : la seule chose que crossplane ne sait pas faire, c'est laisser une dérive non corrigée. |
| compound | hérite — un compound avec un enfant crossplane n'offre pas le Gouverné (tout-ou-rien). |

Impact sur l'existant : **AUCUN** — le défaut est `gere`, une promesse ou une instance qui ne
dit rien garde exactement le comportement d'aujourd'hui.

### terraform (tofu-controller — moteur de référence, pilote LG2)

| Niveau | Réglages rendus par la promesse |
|---|---|
| Observé | `planOnly: true` + `destroyResourcesOnDeletion: false` + `storeReadablePlan: human`. **Constaté au pilote (LG2)** : le plan est produit à la liaison PUIS l'objet SE GARE — zéro pod au repos ; re-diff = re-vérification à la demande (mécanisme tfctl replan, patch de status). Le plan lisible vit dans une **ConfigMap** `tfplan-<ns>-<nom>` (pas un Secret). `approvePlan: disable` (dérive seule) ne vaut que POST-apply — sans état, il n'y a rien à dériver : il ne convient PAS à un Observé jamais appliqué. |
| Gouverné | `approvePlan` vide (le plan attend) + `destroyResourcesOnDeletion: false` ; approbation = `approvePlan: plan-main-<sha>` posé PAR PR, gatée portier. |
| Géré | `approvePlan: auto` + `destroyResourcesOnDeletion` selon l'offre (défaut actuel : true). |
| Liaison | variable de module **`import_id`** (optionnelle, défaut vide) + bloc `import` conditionnel — l'import ne MATÉRIALISE l'état qu'au premier apply (donc à la promotion) ; en Observé le plan montre « will be imported » + le diff. Règle d'or : après alignement, **0 change**. |

### crossplane (éprouvé LG8 sur MR brut ; par le PRODUIT : AU4)

| Niveau | Réglages |
|---|---|
| Observé | `managementPolicies: ["Observe"]` + annotation `crossplane.io/external-name: <id>`. **ÉPROUVÉ sur provider-keycloak (LG8)** : atProvider reflète l'état réel, une divergence déclarée n'écrit RIEN, la suppression du MR laisse la ressource vivre. ⚠️ 3 leçons beta : l'external-name SEUL ne suffit pas (les champs d'IDENTITÉ du forProvider restent requis — « required param 'name' not set » sinon) ; les types du forProvider priment sur l'API du fournisseur (attributes = map de strings) ; `providerConfigRef` explicite avec `kind`. Toujours à éprouver PROVIDER PAR PROVIDER. |
| Gouverné | **NON OFFERT** (la règle « rien ne converge sans déclenchement humain » — voir §4, décision utilisateur) : le provider converge seul par construction. L'échelle crossplane saute d'Observé à Géré, la promotion gatée par le portier. |
| ⚠️ v2 (AU4) | `deletionPolicy` N'EXISTE PAS sur les MRs namespacés v2 (constaté). La non-destruction d'un ADOPTÉ = des `managementPolicies` SANS `Delete` — UNE table `(mode\|liaison)` : observe→`[Observe]` · gere+liaison→`[Observe,Create,Update,LateInitialize]` · greenfield→absentes (défaut serveur `[*]`). CEL d'admission : l'Observé EXIGE la liaison. ⚠️ La convergence à la promotion applique LE DÉCLARÉ — un attribut réel inconnu du déclaré disparaît (le sens fort du Géré, à dire dans l'offre). |
| Géré | politiques complètes. |
| Ligne rouge | **JAMAIS `Observe` sur une `Workspace` provider-terraform** (une Workspace EST une exécution) — l'observé terraform passe par tofu-controller. |

### helm · operator · compound — la couche ArgoCD (set AU)

Ces moteurs n'écrivent jamais directement : leurs pipelines RENDENT des manifestes
qu'**ArgoCD applique**. Le niveau se règle sur l'Application qui les porte — trois
politiques, trois chemins du statestore (le routage par la donnée du claim : AU2) :

| Niveau | Application ArgoCD | Ce que ça garantit |
|---|---|---|
| Observé | **AUCUN `syncPolicy`** | le diff live↔déclaré est calculé et AFFICHÉ, rien n'est jamais appliqué — le diff EST le « will be imported » du monde k8s |
| Gouverné | `automated: {selfHeal: false, prune: false}` | seul un merge APPROUVÉ s'applique ; la dérive reste OutOfSync, VISIBLE (console), jamais corrigée sans geste humain ; rien n'est détruit |
| Géré | `automated: {selfHeal: true, prune: true}` | l'actuel (`kratix-destination.yaml:19`) |

⚠️ **La règle des labels (constatée AU2, la porte a réfuté l'hypothèse initiale)** : la
correspondance Kratix est par SOUS-ENSEMBLE (selectors du work ⊆ labels de la Destination)
et `strictMatchLabels` ne bloque QUE les works aux selectors VIDES. Les Destinations
d'adoption ne portent donc QUE `{adoption: observe|gouverne}` — aucun label partagé avec
worker-1 — sinon les deps de TOUTES les promesses (selector `{environment: platform}`)
entrent dans les chemins d'adoption, et un claim gere peut y tomber (vécu). Le renderer
écrit `{adoption: <mode>}` SEUL pour observe/gouverne, `{environment: platform}` pour gere.
Suppression par niveau, contraste prouvé (AU2) : observé = pur oubli · gouverné = l'objet
SURVIT et ArgoCD le SIGNALE (OutOfSync « requires pruning » — le retrait réel reste un
geste humain) · géré = destruction pilotée.

- **Liaison helm = la CONVENTION DE NOMS** : les values du claim déterminent les noms que le
  chart rend ; mêmes noms = même objet. La promotion applique EN PLACE (SSA) : objets repris,
  **UID inchangés** — le protocole de bascule historique du projet, formalisé en niveau.
- **Test d'alignement (l'analogue du « plan vide »)** : une adoption k8s est ALIGNÉE quand le
  diff ne contient AUCUNE création — uniquement des objets existants. Une création dans le
  diff = on n'adopte pas, on ajoute.
- **Scoping operator** : adopter via operator suppose un **CR EXISTANT** (la liaison = son
  nom). S'il n'y a que les objets enfants sans CR, poser un CR est une CRÉATION, pas une
  adoption — l'offre le dit. Le mode vit en ANNOTATION du claim, jamais dans le spec d'une
  CRD tierce (`strict decoding error` sinon — leçon OP6). Détail : AU7.
- **Compound** : le mode du parent vaut pour TOUS les enfants (tout-ou-rien) ; un compound
  dont UN enfant n'est pas adoptable n'expose pas le mode ; le mode MIXTE est interdit en v1
  (backlog nommé). Détail : AU7.
- Cas particulier conservé : un dépôt git CLIENT existant (legacy externe) suit la même
  échelle en pointant SON dépôt — même mot, même sens.

### script · awx (moteur 7) — l'échelle OUVERTE, mais gatée sur un FAIT par offre (CD9)

L'Observé exige un LECTEUR, et il se CONSTATE offre par offre : `observe.sh` présent dans
la source pour `script` (**l'auteur agit**), `ask_job_type_on_launch: true` sur le job
template pour `awx` (le mode check d'Ansible — **le client agit**). Une offre sans son
fait n'est pas adoptable, et **déclarer l'adoption dessus est REFUSÉ à la génération**
avec les deux sorties nommées : un Observé que le moteur ne peut pas exécuter serait un
contrôle décoratif, pire qu'un contrôle absent. **2 barreaux** (`observe` | `gere`) —
Gouverné non offert par conception (aucune notion de plan), comme crossplane.
Non-destruction d'un adopté : porteur **moteur** — le runner saute `destroy` si
`est_adopte` (§3bis). Le raisonnement complet, dont le **refus du barreau déclaratif**,
est au **§9quater de PROMISE-STANDARD**.

### api (moteur 8) — l'échelle N'EST PAS À CONSTRUIRE, elle est HÉRITÉE

Une offre `api` n'est pas exécutée par un runtime à elle : la désignation des opérations
produit soit un **module terraform** (classe ressource), soit une **promesse script**
(classe action). Conséquence directe, et c'est LA raison du choix d'architecture : une
ressource `api` hérite de l'échelle terraform **en entier** — `planOnly` pour l'Observé,
l'approbation du plan pour le Gouverné, la convergence pour le Géré, et
`destroyResourcesOnDeletion` dérivé d'`est_adopte` comme porteur de non-destruction
(§3bis). La **liaison** est l'identifiant de l'objet dans l'API (`import_id` = l'uuid, l'id
numérique, la clé métier — celui qu'attend l'opération `read`). Le niveau 0 se sert de
l'opération de LISTE de la même spec (connecteur config-driven), donc du même contrat.

Une ACTION `api` (POST seul) n'a, elle, aucun barreau : elle ne possède rien — la règle
générale des actions, pas une limite de ce moteur.

### La matrice complète — 8 moteurs × 4 niveaux, aucune case vide (AU1)

| Moteur \ Niveau | Répertorié (0) | Observé (1) | Gouverné (2) | Géré (3) |
|---|---|---|---|---|
| terraform | catalogue (par source) | `planOnly` ✅ LG2 | `approvePlan` attend ✅ LG3 | `approvePlan: auto` ✅ |
| crossplane | catalogue (par source) | `managementPolicies: [Observe]` ✅ LG8 (MR) ✅ AU4 (par le PRODUIT : liaison+table dans la Composition, uuid inchangé à la promotion) | **non offert** (règle du Gouverné — limite dite, AFFICHÉE dans la description du champ) | policies complètes ✅ (adopté-en-gere = sans Delete, §3 prouvé AU4) |
| helm | catalogue (par source) | app sans sync (le diff) ✅ AU2+AU3 (pilote produit : alignement 0-création, UID inchangés, reprise en place) | app sans selfHeal/prune ✅ AU2 (dérive tenue, objet survit) | l'actuel ✅ |
| operator | catalogue (par source) | idem helm — **CR existant requis** → AU7 | idem helm (CR ; nuance enfants affichée) → AU7 | l'actuel ✅ |
| compound | catalogue (par source) | hérite — tout-ou-rien → AU7 | hérite (sans enfant crossplane) → AU7 | l'actuel ✅ |
| script | catalogue (par source git) | **par offre** — `observe.sh` présent (l'AUTEUR agit) ✅ CD9-B (observe.sh seul tourne, réel intact, marqueur `adopte` gravé) | **non offert** (pas de plan — comme crossplane, l'enum diffère par conception) | l'actuel ✅ CD3 (premier apply = la confrontation ; garde d'appropriation du script) |
| awx | catalogue (par source AWX ✅ CD7) | **par offre** — mode check (`ask_job_type_on_launch`, le CLIENT agit) ✅ CD9-B (`job_type: check` au journal AWX, cible non touchée) | **non offert** (idem) | l'actuel ✅ CD8-B (`apply`=present · `destroy`=absent, identité du fournisseur) |
| api (ressource) | catalogue par l'opération de LISTE de la spec → OA7 | `planOnly` — hérité de terraform → OA7 | `approvePlan` attend + portier iTop — hérité → OA7 | `approvePlan: auto` — hérité → OA2/OA7 (liaison = l'identifiant de l'API) |

Une case « → AUx » = mécanisme DÉFINI, preuve à jouer dans l'objectif nommé. Un badge ne
s'affiche pour un moteur QUE quand sa case est prouvée — jamais d'affichage en avance sur la
mécanique.

### Catalogue (niveau 0)

Connecteur config-driven par SOURCE (http-entities), lecture seule, pagination OBLIGATOIRE
(toute troncature restante est SIGNALÉE, jamais silencieuse), owner mappé ou bac « orphelins »,
noms qualifiés anti-collision.

## 5. Décisions actées (ex-D1/D3)

1. **Le niveau vit PAR INSTANCE** : champ `mode` du CRD produit (injecté par la fabrique,
   défaut `gere`). L'« adoption » au marketplace est une PORTE DE PRÉSENTATION (le même produit,
   formulaire pré-réglé `observe`), pas un produit dupliqué.
2. **La liaison est une variable du MODULE** (`import_id`) : dérivée dans le formulaire comme
   tout champ, transmise comme toute variable — zéro champ plateforme dédié, zéro apprentissage.
3. Les libellés français du §1 sont LA référence d'affichage (sous réserve de validation
   utilisateur finale).

## 6. L'aiguillage d'entrée — où vit le contrat, et le TEST qui l'encadre

L'échelle des §2-§4 ne couvre que ce qui a **une API pilotable**. Il reste deux familles,
chacune avec sa voie : l'**automatisable dont le contrat ne vit nulle part** — script shell,
API REST sans spec, procédure stockée, CLI propriétaire — où le contrat est **DÉCLARÉ**
(moteur `script`, § « Le contrat déclaré » du PROMISE-STANDARD) ; et le
**non-automatisable** — procédures humaines, systèmes fermés, consoles web sans API — où la
plateforme offre une **promesse-ticket** (objectif LG10) : le contrat self-service d'abord
(un formulaire, une demande tracée, une référence rendue), l'exécution HUMAINE derrière, et
l'automatisation plus tard **derrière le même contrat**.

**L'aiguillage** — on y entre par constat, jamais par déclaration :

| Ce que le système expose | → la voie |
|---|---|
| une API pilotable **avec un moteur/provider existant** | un moteur : terraform, crossplane, helm, operator |
| une API pilotable **sans provider**, mais **une spec OpenAPI/Swagger — CONSTATÉE** | le moteur **`api`** : le contrat se DÉRIVE du schéma, les verbes se DÉSIGNENT parmi les opérations — ressource (CRUD désigné) ou action (POST seul) |
| une exécution possible mais **un contrat ILLISIBLE** — CONSTATÉ | le moteur **`script`** (contrat DÉCLARÉ) — ressource ou action **selon les VERBES** ; y compris une API SANS spec, dont le contrat se compose au stylo du Studio |
| une API en LECTURE seule | Répertorié (§2 niveau 0) ou Observé (§2 niveau 1) |
| **aucune API — CONSTATÉE** | **la promesse-ticket** (LG10), classe « Action » |

Trois précisions de frontière :

- un **survey AWX** est un contrat déclaré **dans un système tiers lisible par API** — même
  famille que la déclaration, servie par le moteur **`awx`** (`spec.type: awx` ; la classe
  action/ressource se déduit de la variable d'état du survey — décision CD7) ;
- une **spec OpenAPI/Swagger constatée** rend le contrat **DÉRIVABLE** : c'est la famille des
  moteurs qui LISENT, servie par le moteur **`api`** (`spec.type: api`, § « Promesses API »
  du PROMISE-STANDARD ; set `Objectives/api-derivable/`). L'ordre des deux premières lignes
  est un ORDRE DE PRÉFÉRENCE : là où un provider existe déjà (un module Terraform, un
  provider Crossplane), on le prend — le moteur `api` sert là où personne n'en a écrit,
  ce qui est le cas ordinaire des API internes d'entreprise ;
- une spec qui existe mais qu'on ne peut pas atteindre (derrière une authentification, ou
  servie par une URL qui bouge) ne disqualifie pas ce moteur : la spec se **vendorise** en
  snapshot pinné — c'est de toute façon la règle de gouvernance (voir le § du
  PROMISE-STANDARD).

⚠️ **« Constaté » veut dire mesuré, pas affirmé — pour les DEUX lignes qui en portent la
mention.** « Aucune API » : l'exemple de référence est la création d'une organisation
GitHub — `POST /admin/organizations` rend **404** sur github.com (l'appel n'existe que sur
GitHub Enterprise Server). « Contrat illisible » se démontre pareil : pas de schéma dans
l'artefact, pas de spec, pas de système tiers qui le porte — sinon le moteur `script`
deviendrait l'échappatoire de qui n'a pas envie d'écrire son schéma, exactement comme le
ticket serait l'échappatoire de qui n'a pas envie d'écrire un module.

**Pourquoi cette exigence.** Sans elle, ces motifs institutionnaliseraient le travail
manuel — ou le contrat au rabais — que la plateforme est censée réduire. Le ticket est un
aveu d'absence d'API ; la déclaration est un aveu d'absence de schéma lisible. Ni l'un ni
l'autre n'est un raccourci.

**Et ce que la promesse-ticket ne promet PAS**, écrit sur la carte, dans la description et dans
le corps du ticket : elle ne surveille rien, ne se répare pas, et retirer la demande ne défait
rien. D'où sa **classe distincte** au marketplace (LG9, `entry-kind: action`) : une entrée qui
n'offre pas la même garantie que ses voisines doit se voir comme telle.

## 6bis. Ce que ce contrat NE couvre PAS (dit franchement)

- La migration d'objets DÉJÀ gérés par une autre Composition/outillage (changement de
  propriétaire technique) — un autre sujet, à ne pas confondre avec l'adoption.
- La remédiation par contrôle (liste de contrôles autorisés en Géré) — backlog nommé, hérité de
  l'ancien contrat DTrack.

## 7. Table garantie → test de falsification → où c'est joué

| Garantie | Test | Joué en |
|---|---|---|
| Observé ne peut pas écrire | chaque plan + audit API fournisseur : zéro mutation | LG2 (b) ✅ |
| Le plan dit la vérité (import puis plan vide) | premier plan « will be imported » ; après alignement : 0 add / 0 destroy, seul l'enregistrement protecteur d'archive_on_destroy | LG2 (c) ✅ |
| La dérive s'affiche sans se corriger (Observé) | mutation manuelle → visible à la RE-VÉRIFICATION, non réappliquée | LG2 (d) ✅ |
| Suppression = pur oubli (Observé/Gouverné) | delete claim → ressource intacte ; l'état devient ORPHELIN (constaté — pièce du backlog balayage) | LG2 (e) ✅ |
| Import idempotent | ressource en état + bloc import toujours présent → ni erreur ni ré-import | LG3 (g de LG2, rejoué post-apply) |
| Gouverné bloque sans approbation | merge tenté sans ticket approuvé → rouge ; contenu changé après approbation → re-bloqué | LG3 (a), (e) |
| Géré corrige seul | dérive provoquée → corrigée dans l'intervalle | LG3 (c) |
| Rétrogradation conserve l'état et cesse d'écrire | même tfstate ; plus d'apply ; dérive redevient visible | LG3 (d) |
| Répertorié jamais menteur | horodatage de synchro visible ; caps signalés | LG7 (a)(e) |
| Observé-k8s ne peut pas écrire | app sans sync : UID/RV du décor inchangés ≥ 10 min pendant que le diff est visible | AU3 (b)(c) |
| Adoption k8s alignée = diff sans création | le diff ArgoCD ne montre QUE des updates sur des objets existants | AU3 (b) |
| Un claim gere ne tombe jamais en observe | strictMatchLabels : témoin négatif de routage | AU2 (c) |
| Rien ne converge sans humain (Gouverné) | dérive manuelle OutOfSync non corrigée ≥ 2 cycles ; le merge approuvé, lui, s'applique | AU2 (e) |
| La dérive se VOIT dans la console | dérive provoquée → la fiche affiche « dérive détectée », sans correction | AU6 (f) |
| Rétrograder ne détruit JAMAIS | gere→observe : les fichiers quittent l'app prune:true, l'objet SURVIT (ceinture) | AU3 (f) |
| Promotion k8s = reprise, pas recréation | UID identiques avant/après le premier apply | AU3 (d) · AU7 (c) |
| Une action ne défait rien à la suppression | delete du claim → le geste RESTE fait | CD2 (d) |
| Un échec de script est un échec de demande | script en code ≠ 0 → statut ROUGE, cause lisible — jamais un vert menteur | CD2 (f) · CD3 (e) |
| Une ressource `script` ne s'auto-guérit pas | dérive manuelle → PAS corrigée, et la fiche le dit | CD3 (b) |
| Sans `observe.sh`, aucune surface de dérive | fiche SANS badge (ni « alignée » ni « je ne sais pas ») — la surface n'existe pas | CD3 (g) · CD4 |
| La classe suit les verbes | `run.sh` seul ne peut produire qu'une ACTION ; `apply`+`destroy` qu'une RESSOURCE | CD4 (a) · CD5 (c) |
| Une opération ne se devine jamais | sur une API où `PUT` crée et `POST` modifie (cas réel), la génération SANS désignation est refusée — jamais une déduction par convention | OA4 · OA2 |
| Un contrat dérivé n'exige pas l'indérivable | un champ `required` par la spec mais produit par le SERVEUR (identifiant, horodatage) est retiré du formulaire, et le retrait est RENDU — jamais un formulaire insoumettable, jamais un retrait muet | OA4 (d) · OA2 (h) |
| La spec ne se lit jamais à chaud | l'instance vit sur un snapshot pinné (sha256) : modifier la spec servie par l'API ne change RIEN tant qu'aucune régénération n'a été mergée | OA5 · OA8 |
| La classe suit les OPÉRATIONS | une désignation `create` seule ne peut produire qu'une ACTION ; une combinaison incohérente (delete sans read) est refusée avec ses deux sorties nommées | OA4 (b) · OA3 |
| Un dialecte non supporté est DIT | WSDL/GraphQL/RAML, ou un `$ref` distant → refus guidé nommant la sortie (moteur `script` + stylo, ou vendorisation) — jamais un parse silencieusement partiel | OA4 (b) |
