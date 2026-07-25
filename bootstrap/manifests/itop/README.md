# iTop — l'ITSM de répétition

> Instance interne servant de **doublure de l'ITSM du client**, exactement comme
> `bootstrap/manifests/ldap/` sert de doublure à son Active Directory. Le cluster
> est chez Scaleway, le GitLab et l'iTop du client sont chez lui : les réseaux
> sont disjoints, il faut une scène de répétition. **Ce n'est jamais l'ITSM de
> production du client.**

## Ce que ça déploie

| Ressource | Rôle |
|---|---|
| `00-namespace.yaml` | Namespace, vague `-2` (gotcha R-TPL-7 du projet) |
| `01-bootstrap-credentials.yaml` | Hooks PreSync : RBAC + Job qui **génère** `itop-credentials` s'il n'existe pas |
| `02-mariadb.yaml` | MariaDB 10.11 en StatefulSet (iTop ne parle que MySQL/MariaDB) |
| `03-install-scripts.yaml` | Installation sans interface + configuration (LDAP, URL, comptes) |
| `04-itop.yaml` | PVC, Deployment (2 initContainers), Service |
| `05-ingress.yaml` | `https://itop.212-47-226-56.nip.io`, TLS `letsencrypt-prod` |
| `06-seed-job.yaml` | Jeu d'essai **rejouable**, par l'API REST |

## L'image

Construite depuis la **release officielle Combodo** (Combodo ne publie aucune
image ; on refuse une image communautaire pour la couche d'approbation) :
`new-cluster/native/itop-image/` → `./build.sh`.

Après la poussée, **épingler le digest** dans `04-itop.yaml` (trois occurrences :
les deux initContainers et le conteneur) — standard du projet.

## Récupérer les identifiants (Younes)

Ils sont générés **dans le cluster** et n'existent nulle part ailleurs : ni en
Git, ni dans les journaux, ni dans un scellé. Contrepartie assumée : **les
données sont reconstructibles depuis Git, pas les identifiants.**

```bash
export KUBECONFIG=~/Projects/scaleway/kubeconfig/kubeconfig-k8s-for-kratix.yaml

# Mot de passe de l'administrateur iTop (login : admin)
kubectl -n itop get secret itop-credentials -o jsonpath='{.data.ITOP_ADMIN_PASSWORD}' | base64 -d | pbcopy

# Mot de passe du compte de service du portail (login : svc-portal)
kubectl -n itop get secret itop-credentials -o jsonpath='{.data.ITOP_REST_PASSWORD}' | base64 -d | pbcopy
```

`pbcopy` met la valeur dans le presse-papiers **sans l'afficher** — c'est la
convention du projet (cf. `tools/kc-user-password.sh`).

## Les comptes

| Login | Type | Profils | Pour quoi |
|---|---|---|---|
| `admin` | local | Administrator + REST Services User | Administration, amorçage du jeu d'essai |
| `svc-portal` | local | REST Services User, Service Desk Agent, Change Supervisor | **Le compte de Backstage** — moindre privilège volontaire |
| `jdupont` | LDAP | Service Desk Agent | Connexion via l'annuaire |
| `mmartin` | LDAP | Change Approver | Connexion via l'annuaire, approuve les changements |

## L'API REST

```
POST https://itop.212-47-226-56.nip.io/webservices/rest.php?version=1.3
     auth_user=<login>&auth_pwd=<mdp>&json_data={"operation":"core/get",...}
```

`secure_rest_services` est laissé à **true** : seuls les comptes portant le
profil `REST Services User` sont admis. Le laisser à `false` ouvrirait l'API à
tout compte authentifié.

**Références de tickets** (formats natifs iTop, vérifiés dans la release 3.2.3-1) :
`Change` → `C-000123` · `UserRequest` → `R-000123` · `Incident` → `I-000123`.

⚠️ En mode ITIL, **`Change` est une classe abstraite** : les objets créés sont
des `NormalChange` / `RoutineChange` / `ApprovedChange` / `EmergencyChange`.
Une requête `SELECT Change WHERE ref = …` fonctionne (elle renvoie la
sous-classe), mais une **création** doit désigner une sous-classe concrète.

États réels du cycle de vie d'un `Change` (les valeurs à mettre dans la requête
OQL de configuration d'IT2 — **elles ne sont jamais en dur dans le code**) :
`new, validated, rejected, assigned, plannedscheduled, approved, notapproved,
implemented, monitored, closed`.
Noter `plannedscheduled` et non `planned` : c'est précisément le genre d'écart
qui condamne un code qui coderait les états en dur.

## Idempotence

- Le Job d'amorçage ne crée le Secret **que s'il est absent** (son Role n'a même
  pas le droit `update` : un second passage ne *peut pas* écraser des
  identifiants en service).
- L'initContainer d'installation constate l'état **des deux côtés** (fichier de
  configuration ET table `priv_module_install`) avant de décider. Déjà installé →
  il ne réinstalle rien, il se contente de ré-appliquer la configuration.
- Le Job de jeu d'essai cherche chaque objet par OQL avant de le créer.

## Le LDAP

iTop est branché sur l'`openldap` du cluster (`ou=users,dc=platform,dc=local`),
en **liaison anonyme** pour la recherche. Le module `authent-ldap` n'est même pas
*découvert* si l'extension PHP `ldap` manque (`module.authent-ldap.php` est
enveloppé dans un `if (function_exists('ldap_connect'))`) : c'est pour cela que
le Dockerfile l'installe explicitement.

Un utilisateur se connecte en LDAP si — et seulement si — il existe un objet
`UserLDAP` portant son `login`. Le mot de passe n'est jamais stocké dans iTop :
il est vérifié auprès de l'annuaire.

Chez le client, seules quatre valeurs changent (`itop-env`) :
`ITOP_LDAP_HOST`, `ITOP_LDAP_BASE_DN`, `ITOP_LDAP_USER_QUERY`
(`(sAMAccountName=%1$s)` pour un AD), et éventuellement un DN de liaison si la
lecture anonyme est interdite.

## Limites assumées

- L'**extension d'approbation Combodo** peut être sous licence chez le client :
  rien ici n'en dépend. Le cycle de vie natif d'un `Change` suffit à la preuve.
- L'installation d'iTop est nativement un **assistant web** : elle est donc
  faite sans interface par un initContainer, et l'assistant est fermé au réseau
  (`<Location /setup> Require all denied` dans la configuration Apache).
