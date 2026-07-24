# Audit d'encapsulation du catalogue (CT3 — loi 6) · 2026-07-24

Test appliqué champ par champ : « un demandeur pourrait-il légitimement mettre une
autre valeur ? » (PROMISE-STANDARD §10). Catalogue audité : 6 promesses.

| Brique | Champ | Verdict | Action |
|--------|-------|---------|--------|
| workspace | team | ✅ légitime (auto-rempli RequesterTeamPicker O5, dérivé de l'identité) | — |
| workspace | environment, tier, mesh | ✅ légitimes (vrais choix demandeur, enums bornées) | — |
| teamaccess | group | ✅ libre au niveau brique (groupes hors-équipe possibles) ; `team-<team>` exigé par workspace | **H2 ✓** contrat déclaré (PR #77) + defaultName possible (CT4) |
| teamaccess | users | ✅ légitime (picker catalogue User) | — |
| keycloak-group | group, role | ✅ légitimes (brique interne, `role` = vrai choix d'onboarding) | H2 ✓ provides déclaré |
| keycloak-group | realm | ⚠️ mono-valeur MAIS brique `internal` (aucun formulaire demandeur) ; masqué à la composition par teamaccess | **H1 ✓ déjà fait** (hide+défaut dans la recette) |
| keycloak-member | realm | idem keycloak-group | H1 ✓ déjà fait |
| **user** | **realm** | ❌ **mono-valeur EXPOSÉE au demandeur** (template User, éditable → corruption possible pour zéro valeur) | **H0 APPLIQUÉ (CT3)** : `ui:widget: hidden` + défaut `platform` matérialisé — annotation pilote + PR durable (spec.uiSchema au claim) |
| user | username, email, firstName, lastName | ✅ légitimes | — |
| user | team | ✅ auto-rempli (RequesterTeamPicker) | — |
| user | techLead | ✅ légitime (gate de gouvernance — le merge de la PR de claim est l'acte d'admission) | — |
| promise-factory | (méta) | ✅ champs d'authoring, tous légitimes ; non-public | — |

**Mesures** : 17 champs audités · **1 éliminé** (user.realm — la classe de bug « realm
corrompu par un demandeur » est supprimée) · 2 confirmés déjà encapsulés (H1) ·
2 couverts par contrat (H2).
