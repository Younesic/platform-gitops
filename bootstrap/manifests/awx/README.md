# AWX — moteur d'exécution Ansible + cible « legacy » témoin

Brique GitOps de l'objectif **AN1** (`backstage-platform/Objectives/ansible/`).
Elle donne à la plateforme un exécuteur pour le parc **non-Kubernetes** : VM,
middleware, appliances, Windows, legacy — tout ce qui a un SSH mais aucun
contrôleur qui converge.

> **Scène de répétition.** Le client possède déjà AWX / Ansible Automation Platform,
> on-premise ; notre cluster est chez Scaleway. Cette instance en est la **doublure**,
> exactement comme OpenLDAP simule son annuaire. On ne lui vend pas un outil de plus :
> on donne un portail, une gouvernance et une piste d'audit à ce qu'il fait déjà.

## Ce que contient le dossier

| Fichier | Rôle |
|---|---|
| `00-namespace.yaml` | Namespace, vague −2 (R-TPL-7) |
| `01-bootstrap-credentials.yaml` | **PreSync** — génère les identifiants **dans le cluster** |
| `02-operator-crds.yaml` | awx-operator 2.19.1, CRD (rendu vendorisé) |
| `03-operator.yaml` | awx-operator 2.19.1, RBAC + manager (rendu vendorisé) |
| `04-db.yaml` | PostgreSQL CloudNativePG (base externe pour AWX) |
| `05-awx.yaml` | Le CR `AWX` — l'opérateur en dérive web / task / redis / Ingress |
| `06-keycloak-client.yaml` | Client OIDC Keycloak (Crossplane, identity-as-code) |
| `07-legacy-vm.yaml` | **La cible témoin** : un serveur SSH sans API Kubernetes |
| `08-playbooks.yaml` | Le playbook + son archive HTTP (projet AWX) |
| `09-seed-job.yaml` | **PostSync** — jeu d'essai rejouable, par l'API |

## Versions, et comment elles ont été vérifiées

| Composant | Version | Vérification |
|---|---|---|
| awx-operator | **2.19.1** (2024‑07‑02) | `gh api repos/ansible/awx-operator/releases/latest` **et** `.../tags` **et** les tags actifs sur quay.io : c'est la **dernière version publiée**. La branche `devel` continue d'avancer (commits en 2026) mais **aucune version n'a été taguée depuis**. |
| AWX | **24.6.1** | Version appariée à l'opérateur (même date de publication). |
| awx-ee | **24.6.1** | Idem. `latest` a été rebâti en 2026 → jamais utilisé, tag mouvant. |

**Toutes les images sont épinglées par empreinte.** Pour les images AWX, le levier
est `RELATED_IMAGE_*` sur le déploiement de l'opérateur : sans elles, l'opérateur
compose `image:tag` (`roles/installer/tasks/resources_configuration.yml`) et un tag
peut changer sous nos pieds.

**Pourquoi un rendu kustomize vendorisé et pas un chart :** l'awx-operator n'a pas de
dépôt de charts officiel (`https://ansible.github.io/awx-operator/index.yaml` → 404).
Un chart existe sous `ansible-community`, mais il est lui-même **généré à partir de ce
rendu kustomize** (`Makefile: helm-chart-generate`). On vendorise donc la source
d'autorité — le geste déjà fait pour les CRD Kratix (`bootstrap/manifests/kratix/`).

Reproduire le rendu :

```bash
curl -sSL https://github.com/ansible/awx-operator/archive/refs/tags/2.19.1.tar.gz | tar xz
cat > overlay/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: awx
namePrefix: awx-operator-
resources: [../awx-operator-2.19.1/config/crd, ../awx-operator-2.19.1/config/rbac, ../awx-operator-2.19.1/config/manager]
images:
  - name: quay.io/ansible/awx-operator
    digest: sha256:7302e0c8e5a79c11275848b36c63c61d8e7487840164c109b7cda9aa93456901
EOF
kustomize build overlay
```

Les cinq écarts assumés par rapport au rendu brut sont énumérés en tête de
`03-operator.yaml`.

## Les identifiants — générés ici, jamais vus

Aucun mot de passe ne transite : le Job d'amorçage les tire de `/dev/urandom` (et la
paire SSH de `ssh-keygen`) et les envoie **directement** dans `kubectl create secret`.
Rien n'est affiché, rien n'est en Git.

**Contrepartie assumée :** l'instance n'est pas reconstructible à l'identique depuis
Git seul. Les *données* le sont (base + jeu d'essai rejouable), les *identifiants* non.

Le Job n'a le droit que de `get` et `create` sur les Secrets : un second passage ne
peut pas écraser des identifiants en service.

| Secret | Contenu | Créé par |
|---|---|---|
| `awx-admin-password` | mot de passe de `admin` | amorçage |
| `awx-db-credentials` | rôle PostgreSQL (lu par CNPG) | amorçage |
| `awx-postgres-configuration` | la même chose, au format attendu par AWX | amorçage |
| `awx-legacy-ssh` | paire SSH de la cible témoin | amorçage |
| `awx-oidc-client` | secret du client Keycloak | Crossplane |
| `awx-api-token` | jeton d'API pour l'**opérateur Ansible** (AN2) | jeu d'essai |
| `awx-secret-key` | clé de chiffrement d'AWX | awx-operator |

### Récupération (pour Younes)

```bash
export KUBECONFIG=~/Projects/scaleway/kubeconfig/kubeconfig-k8s-for-kratix.yaml

# Mot de passe de l'administrateur AWX (à coller directement, sans passer par l'écran)
kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d | pbcopy

# Jeton d'API (celui qu'utilisera l'opérateur Ansible)
kubectl -n awx get secret awx-api-token -o jsonpath='{.data.token}' | base64 -d | pbcopy
```

> La connexion **OIDC Keycloak** est le chemin nominal ; le compte `admin` local est
> la porte de service (jeu d'essai, dépannage).

## Rejouer le jeu d'essai

Il est idempotent : chaque objet est cherché par son nom avant d'être créé.

```bash
kubectl -n awx delete job awx-seed-manuel --ignore-not-found
kubectl -n awx create job awx-seed-manuel --from=job/awx-seed
kubectl -n awx logs -f job/awx-seed-manuel
```

## La cible témoin

`legacy-vm` est un pod qui ne porte qu'un serveur SSH : **il n'a aucune API
Kubernetes**, on ne l'atteint qu'en SSH avec la clé du Secret `awx-legacy-ssh`.
Son `/opt/legacy` est un volume persistant — un vrai serveur garde son état au
redémarrage, et sans cela on confondrait « dérive » et « redémarrage ».

Constater l'effet du playbook :

```bash
kubectl -n awx exec deploy/legacy-vm -- cat /opt/legacy/<nom-du-service>.conf
```

**Limite honnête :** c'est un pod, pas une machine. Il prouve le *chemin* (clé SSH,
identifiant machine, inventaire, effet observable et idempotent), pas le comportement
d'un système d'exploitation complet. Il installe `openssh`/`python3` au démarrage
depuis le miroir Alpine : dépendance d'egress, assumée et **bruyante** (si elle
tombe, le pod ne démarre pas — jamais un demi-serveur qui répond).

## Modifier le playbook

Le contenu Ansible vit dans la ConfigMap de `08-playbooks.yaml` et est distribué à
AWX en **archive HTTP** (type de projet « Remote Archive »), servie dans le cluster :
zéro identifiant, zéro dépendance sortante, et le contenu reste dans Git.

⚠️ Après modification, **incrémenter `playbooks-revision`** dans le modèle de pod du
même fichier : ArgoCD ne redémarre pas un pod parce qu'une ConfigMap a changé.

## Ce qui, chez le client, sera différent

- **L'AAP est la sienne** : cette instance disparaît, l'opérateur Ansible pointe la sienne.
- **L'authentification sera probablement LDAP** et non OIDC — un réglage, pas une architecture.
- **Les projets viendront de son GitLab**, pas d'une archive HTTP.
