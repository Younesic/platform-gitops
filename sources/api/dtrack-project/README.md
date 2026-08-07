# Source `api` — Projet Dependency-Track

Pilote du **moteur `api`** (PROMISE-STANDARD §9quinquies) : le contrat se DÉRIVE du
schéma de la spec, les verbes se DÉSIGNENT parmi ses opérations.

## Le contrat d'origine — la spec, PINNÉE

| | |
|---|---|
| fichier | `spec.json` (snapshot, 446 708 octets) |
| dialecte | OpenAPI **3.0.1**, 153 chemins |
| sha256 | `6860fd79ae5d3d97c619ac14c9d7aca11d24be6fb4b6a276f18d01b91033d97d` |
| origine | `https://dtrack.212-47-226-56.nip.io/api/openapi.json`, relevée le 2026-08-07 |

La plateforme ne lit **jamais** cette spec à chaud. Une spec qui change = une
régénération, par une PR. C'est le pin d'un chart ou d'un tag de module, appliqué à un
document.

## La DÉSIGNATION — et pourquoi elle ne peut pas se deviner

| rôle | opération | operationId |
|---|---|---|
| `create` | **PUT** `/api/v1/project` | `createProject` |
| `read` | GET `/api/v1/project/{uuid}` | `getProject` |
| `update` | **PATCH** `/api/v1/project/{uuid}` | `patchProject` |
| `delete` | DELETE `/api/v1/project/{uuid}` | `deleteProject` |

Deux pièges, tous deux **mesurés** sur l'API réelle :

1. **`PUT` crée et `POST` modifie** — l'inverse exact de la convention REST. Une
   machine qui aurait déduit les verbes aurait produit un module qui *modifie* quand
   on lui demande de *créer*.
2. **`POST` modifie… mais sur la COLLECTION.** Dirigé vers l'item
   (`/api/v1/project/{uuid}`) il rend **405**. L'update de l'item, c'est `PATCH`.
   ⇒ La désignation ne porte pas seulement le VERBE : elle porte le verbe **et le
   chemin**.

## Le contrat exposé au demandeur

Dérivable du schéma `Project` de la spec : `nom` (requis, ≤ 255) · `version_projet` ·
`classifier` (l'énumération de la spec) · `description` · `import_id` (la liaison
d'adoption).

⚠️ **Les `required` menteurs.** Le schéma `Project` déclare
`required: [lastBomImport, name, uuid]` — mais `uuid` et `lastBomImport` sont produits
**par le serveur**. Les exposer donnerait un formulaire que personne ne peut soumettre.
Ils sont donc RETIRÉS du contrat, et ce retrait est dit (§9quinquies, « la règle des
required menteurs »).

## Les identifiants

Par **fichiers montés** dans le runner (`/dtrack/DTRACK_URL`, `/dtrack/DTRACK_API_KEY`,
depuis le Secret `default/dtrack-api-creds`), lus par `file()`.

Pourquoi pas des variables terraform, contrairement à harbor-project qui passe par
l'environnement : le provider `restful` n'a **aucun** support de variables
d'environnement (`base_url` est requis en configuration — vérifié sur son schéma), et
une variable terraform voyagerait dans le plan lisible. `file()` est évalué à
l'exécution : le plan ne garde que l'expression, jamais la valeur.

La clé vient de l'équipe DT **`plateforme-api`**, qui n'a que
`PORTFOLIO_MANAGEMENT` + `VIEW_PORTFOLIO`. Elle est fabriquée dans le cluster par
`bootstrap/manifests/dependency-track/api-key-seed.yaml` et n'est jamais affichée.

## L'exécuteur

`magodo/restful` — choisi **au banc, sur pièces** (OA2). Le concurrent
`Mastercard/restapi` a été écarté pour une raison décisive et mesurée : sur une
ressource strictement inchangée, son plan n'est **jamais vide** (il veut réécrire toute
la réponse serveur). Le barreau Gouverné demanderait une approbation à chaque tour sur
du bruit, et la dérive serait perpétuellement fausse. Détail dans
`Objectives/api-derivable/proofs/OA2-evidence.txt`.
