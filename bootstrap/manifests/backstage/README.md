# Backstage ⇄ Kratix — le portail développeur

Portail self-service déployé sur `k8s-for-kratix`, branché sur Keycloak (realm `platform`) et
sur les promises Kratix. Réconcilié en GitOps par ArgoCD (app `backstage`, app-of-apps `platform-identity`).

URL : https://backstage.212-47-226-56.nip.io

---

## ⚠️ L'app déployée = `backstage-platform/`, PAS `backstage/`

Le code source du portail vit dans **`self-prov/backstage-platform/`** (Backstage **1.52**, realm
`platform`, branding Attijari, sign-in **Guest + Keycloak**). L'ancien `self-prov/backstage/`
(Backstage 1.39, realm `awb`, ancien cluster) est **obsolète** — ne plus le builder/déployer.

Build image : `cd backstage-platform && yarn build:all` puis
`docker buildx build --platform linux/amd64 -f packages/backend/Dockerfile -t harbor.212-47-226-56.nip.io/platform/backstage:<tag> --push .`

---

## Les 2 briques (kubernetes-ingestor Terasky)

L'ingestion repose sur **`@terasky/backstage-plugin-kubernetes-ingestor`** (backend, watch-based) —
un seul moteur générique qui observe les CRD du cluster. Config dans `app-config.yaml` → `kubernetesIngestor`.

### Brique A — Templates depuis le SCHEMA de la promise
- Provider : **`XRDTemplateEntityProvider`** (via `genericCRDTemplates.crds`).
- Il lit l'**`openAPIV3Schema`** de la CRD et **génère automatiquement un Template Backstage**
  (les `properties` du `spec` → champs de formulaire, avec descriptions/enums/contraintes).
  **Zéro template écrit à la main.**
- Action générée : `terasky:crd-template` → `publish:github:pull-request` (le form crée le claim + ouvre une PR).
- **Ajouter une promise au portail = 1 ligne** dans `genericCRDTemplates.crds`.

### Brique B — Claims en entités du catalogue
- Provider : **`KubernetesEntityProvider`** (via `components.customWorkloadTypes`).
- Chaque claim (`TeamNamespace`, `TeamProject`) devient une **entité du catalogue**.

---

## Les 3 niveaux (vocabulaire — important)

| Niveau | Quoi | Représenté ? |
|--------|------|--------------|
| 1. **Promise** | l'API (le *type* demandable) | Template (Brique A) |
| 2. **Claim / Resource Request** | l'instance demandée (le CR `demo-bs`) | **entité catalogue (Brique B) — FAIT** |
| 3. **Provisionné** | la sortie du pipeline (le `Namespace team-*`, quota, RBAC, workloads) | **FAIT — push (voir §Niveau 3)** |

> Le niveau 2 = ce que représente aussi Syntasso (son `kratix-resource` = le Resource Request, pas l'objet brut).

---

## Le KIND d'entité : `Component` + `spec.type: kratix-resource` (façon Syntasso)

Recherche faite sur Syntasso (sources en bas) :
- Syntasso **n'utilise pas `kind: Resource`** — il met **`kind: Component` + `spec.type: kratix-resource`**
  (et `kratix-promise` pour les promises). Différenciation par `spec.type`, pas par `kind`.
- Raison : une instance de promise est une chose **possédée/gérée/interactive** (≈ Component), pas
  de l'infra passive ; + l'écosystème Backstage est Component-centré (plus découvrable, UX riche).
- `spec.type` préserve la sémantique « c'est une ressource » sans perdre les avantages Component.

→ On s'aligne : `kubernetesIngestor.components.customWorkloadTypes[].defaultType: kratix-resource`.

> Alternative `kind: Resource` (`components.ingestAsResources: true`) = plus « correct sur le papier »
> mais prive de l'UX Component, pour un gain que `spec.type` donne déjà. Écartée.

---

## L'UI custom des entités `kratix-resource`

La page d'entité Backstage **par défaut n'est pas adaptée**. Syntasso a une `KratixResourceEntityPage`
custom — **mais elle est dans `@syntasso/plugin-ske-frontend`, CLOSED-SOURCE (enterprise, npm privé)**.

Équivalent **open-source** (même famille Terasky que l'ingestor, Apache-2.0) :
- **`@terasky/backstage-plugin-kubernetes-resources-frontend`** (graphe interactif ressource + dépendances, YAML, events).
- **`@terasky/backstage-plugin-kubernetes-resources-permissions-backend`** (agrégation + RBAC).

Câblage : `packages/app/src/components/catalog/EntityPage.tsx` → un case
`isComponentType('kratix-resource')` rend une page custom (Overview + onglet **Resources** =
`KubernetesResourcesPage` + onglet **Kubernetes** + Dependencies). Le graphe Terasky montre la
ressource **ET ce qu'elle a provisionné** → c'est le **pont naturel vers le niveau 3**.

---

## Niveau 3 — le provisionné comme entités `Resource` (PUSH, façon Syntasso)

Le provisionné (namespace + quota + RBAC, demain DB/bucket/workload) est représenté comme
des entités **`kind: Resource`** reliées au claim. Mécanisme **push** (≠ watch) :

1. **Un container SÉPARÉ `backstage-generator`** (R-L3-2 / R-CORE-2, **SoC façon Syntasso**) — ajouté
   APRÈS `render` dans le workflow — émet la fiche. **Le core de provisioning `promise-render` reste
   AGNOSTIQUE** (il ne connaît pas Backstage ; swappe ce container = swappe le portail). Pour CHAQUE
   claim il écrit une `Resource` dans **`/kratix/output/backstage/`**. **Hybride** : si la baseline
   fournit sa propre fiche `backstage.io` → elle est utilisée (personnalisable : une DB y met son lien
   de connexion) ; sinon → **fiche par défaut générique** (`owner = group:default/team-<slug>`,
   `dependencyOf: [component:<ns>/<claim>]`, label-selector k8s).
2. **Routage agnostique** : `route.sh add_directory_route backstage backstage` → clé matrice
   **`selectors_backstage`** → **Destination `backstage`** (= repo `kratix-state`, path `backstage/`).
   **Pas de hardcode** : changer la cible = éditer la `routing-matrix` (R-RT-1).
3. **ArgoCD ne voit pas `backstage/`** (l'app kratix-destination ne lit que `worker-1/`) → aucune
   tentative d'appliquer une fiche comme du k8s.
4. **Backstage lit via son provider git STANDARD** (`catalog.providers.github`, repo `kratix-state`,
   path `/backstage/**/backstage/*.yaml`) — **0 code custom**. Module `@backstage/plugin-catalog-backend-module-github`.
5. **Cleanup automatique** : au `delete` du claim, Kratix prune la fiche → l'entité disparaît.

> C'est exactement le pattern Syntasso (Destination dédiée `environment: backstage` + sous-dir
> `backstage/` + scheduling directory-based), **plus** notre routage agnostique par la matrice.
> Décision **push vs watch** : push choisi pour la **personnalisation** (la promise décrit sa fiche).

---

## Identité / OIDC

- Realm unique **`platform`** ; client `backstage` (Crossplane `Client`, CONFIDENTIAL).
- **Un seul client partagé local + cluster** : ses `validRedirectUris` incluent
  `https://backstage.212-47-226-56.nip.io/...` **et** `http://localhost:7007|3000/...` (dev `yarn start`).
- Secret OIDC via `backstage-oidc-client` (clé `attribute.client_secret`, env `KEYCLOAK_CLIENT_SECRET`).
- Sign-in = **Guest + Keycloak** (les 2 providers dans `auth.providers`).

---

## Dev LOCAL (voir les templates/ressources sur localhost:3000)

`backstage-platform/app-config.local.yaml` (non commité) contient l'accès k8s + l'ingestor :
- `kubernetes.clusterLocatorMethods` → cluster `k8s-for-kratix` + **token SA `backstage`** (30j) + `skipTLSVerify`.
- même bloc `kubernetesIngestor` que le cluster.
→ `yarn start`, attendre quelques min (scan ingestor), `/create` montre les templates, `/catalog` les ressources.

---

## Fichiers (ce dossier)

| Fichier | Rôle |
|---------|------|
| `app-config.yaml` | ConfigMap : la config Backstage **complète** (montée, `--config /app/config/app-config.yaml`) |
| `deployment.yaml` | Deployment (image `backstage:<tag>`, env DB/OIDC/backend) |
| `keycloak-client.yaml` | `Client` Crossplane `backstage` (redirects local+cluster) + group mapper |
| `db.yaml` | CNPG `backstage-db` |
| `rbac.yaml` | SA `backstage` + ClusterRole (lit core/apps/CRD/`platform.example.io`) |
| `ingress.yaml`, `sealed-secrets.yaml` | ingress TLS + secrets |

---

## Sources de recherche
- [SKE Backstage plugins (enterprise, closed-source)](https://docs.kratix.io/ske/integrations/backstage/plugins)
- [Kratix & Backstage (open-source)](https://docs.kratix.io/main/how-kratix-complements/backstage)
- [TeraSky OSS Backstage plugins](https://terasky-oss.github.io/backstage-plugins/) · [GitHub](https://github.com/TeraSky-OSS/backstage-plugins)
