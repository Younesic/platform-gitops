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
- **Interdit** : appliquer sans approbation (le défaut est fermé) ; corriger la dérive seul ;
  détruire (même à la suppression du claim) ; escalader des droits non déclarés.
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
| tout niveau → suppression du claim | oui | suppression de la demande | Observé/Gouverné : pur oubli. Géré : le contrat de l'offre s'applique (destruction si déclarée) |
| Répertorié → rien | oui | l'entité disparaît quand la source ne la liste plus (full-mutation) | — |

Règles transverses : une transition ne saute jamais la porte quand elle ÉLARGIT les droits
(monter = approuver) ; descendre est libre d'approbation mais tracé (PR) ; l'affichage ne
PRÉCÈDE jamais la mécanique (un badge dit ce qui est, pas ce qui est demandé).

## 4. Déclinaison par moteur

### terraform (tofu-controller — moteur de référence, pilote LG2)

| Niveau | Réglages rendus par la promesse |
|---|---|
| Observé | `planOnly: true` + `destroyResourcesOnDeletion: false` + `storeReadablePlan: human`. **Constaté au pilote (LG2)** : le plan est produit à la liaison PUIS l'objet SE GARE — zéro pod au repos ; re-diff = re-vérification à la demande (mécanisme tfctl replan, patch de status). Le plan lisible vit dans une **ConfigMap** `tfplan-<ns>-<nom>` (pas un Secret). `approvePlan: disable` (dérive seule) ne vaut que POST-apply — sans état, il n'y a rien à dériver : il ne convient PAS à un Observé jamais appliqué. |
| Gouverné | `approvePlan` vide (le plan attend) + `destroyResourcesOnDeletion: false` ; approbation = `approvePlan: plan-main-<sha>` posé PAR PR, gatée portier. |
| Géré | `approvePlan: auto` + `destroyResourcesOnDeletion` selon l'offre (défaut actuel : true). |
| Liaison | variable de module **`import_id`** (optionnelle, défaut vide) + bloc `import` conditionnel — l'import ne MATÉRIALISE l'état qu'au premier apply (donc à la promotion) ; en Observé le plan montre « will be imported » + le diff. Règle d'or : après alignement, **0 change**. |

### crossplane (2ᵉ moteur, GATED LG8 — beta)

| Niveau | Réglages |
|---|---|
| Observé | `managementPolicies: ["Observe"]` + annotation `crossplane.io/external-name: <id>`. **ÉPROUVÉ sur provider-keycloak (LG8)** : atProvider reflète l'état réel, une divergence déclarée n'écrit RIEN, la suppression du MR laisse la ressource vivre. ⚠️ 3 leçons beta : l'external-name SEUL ne suffit pas (les champs d'IDENTITÉ du forProvider restent requis — « required param 'name' not set » sinon) ; les types du forProvider priment sur l'API du fournisseur (attributes = map de strings) ; `providerConfigRef` explicite avec `kind`. Toujours à éprouver PROVIDER PAR PROVIDER. |
| Gouverné | politiques élargies SANS `Delete` + `deletionPolicy: Orphan` ; la porte reste la PR gatée (pas de mécanisme d'attente natif équivalent à approvePlan → le Gouverné crossplane est « changement par PR approuvée », dérive non corrigée impossible à garantir nativement : LIMITE DITE, à trancher en LG8). |
| Géré | politiques complètes. |
| Ligne rouge | **JAMAIS `Observe` sur une `Workspace` provider-terraform** (une Workspace EST une exécution) — l'observé terraform passe par tofu-controller. |

### ArgoCD (legacy k8s qui a DÉJÀ un dépôt git)

`syncPolicy` absent = Observé (le diff est visible, rien n'est appliqué) → sync manuel = Gouverné
→ `automated + selfHeal (+ prune déclaré)` = Géré. Hors périmètre des premiers objectifs ;
décliné ici pour que le mot ait le même sens le jour venu.

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

## 6. Le legacy SANS API — et le TEST D'ENTRÉE qui l'encadre

L'échelle des §2-§4 ne couvre que ce qui a **une API pilotable**. Pour le reste — procédures
humaines, systèmes fermés, consoles web sans API — la plateforme offre une **promesse-ticket**
(objectif LG10) : le contrat self-service d'abord (un formulaire, une demande tracée, une
référence rendue), l'exécution HUMAINE derrière, et l'automatisation plus tard **derrière le
même contrat**.

**L'aiguillage** — on y entre par constat, jamais par déclaration :

| Ce que le système expose | → le bon barreau |
|---|---|
| une API pilotable (écriture) | un moteur : terraform, crossplane, helm, operator |
| une API en LECTURE seule | Répertorié (§2 niveau 0) ou Observé (§2 niveau 1) |
| **aucune API — CONSTATÉE** | **la promesse-ticket** (LG10), classe « Action » |

⚠️ **« Constatée » veut dire mesurée, pas affirmée.** L'exemple de référence : la création
d'une organisation GitHub — `POST /admin/organizations` rend **404** sur github.com (l'appel
n'existe que sur GitHub Enterprise Server). C'est ce genre de trace qu'on exige avant d'admettre
une promesse-ticket.

**Pourquoi cette exigence.** Sans elle, le motif devient l'échappatoire de qui n'a pas envie
d'écrire un module — et la plateforme institutionnaliserait le travail manuel qu'elle est censée
réduire. Le ticket est un aveu d'absence d'API, pas un raccourci.

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
