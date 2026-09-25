THIS FILE IS GENERATED.
DO NOT EDIT MANUALLY.

# Player Documentation Reference

Addon version: 0.6.5

## Dibs audit history

- **ID:** `ledger.audit.history`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Dib Balance

- **ID:** `ledger.balance`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Your available Dibs are scoped to this guild and season. A qualifying finalized award or authorized adjustment changes the balance.
**Francais:** Vos Dibs disponibles sont propres a cette guilde et a cette saison. Un gain eligible finalise ou un ajustement autorise modifie le solde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Loot eligibility

- **ID:** `loot.eligibility`
- **Category:** `governance`
- **Audience:** gm, officer, player

**English:** Shows whether a loot category may use Dibs under the active guild policy, and why a category is blocked or needs review.
**Francais:** Indique si une categorie de butin peut utiliser les Dibs selon la politique active, et pourquoi elle est bloquee ou a verifier.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Request audit timeline

- **ID:** `officer.audit.timeline`
- **Category:** `ledger`
- **Audience:** gm, officer, player

**English:** Shows recorded dates, actions, and available reasons. Older events are evidence, not editable balance controls.
**Francais:** Affiche les dates, actions et raisons disponibles. Les anciens evenements sont des preuves, pas des soldes modifiables.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Player raid readiness

- **ID:** `player.readiness`
- **Category:** `setup`
- **Audience:** gm, officer, player

**English:** Summarizes whether current guild setup and context are ready for live loot. An unavailable check is not a personal penalty; contact an Officer if the state remains blocked.
**Francais:** Resume si la configuration de guilde et le contexte actuel sont prets pour le butin en direct. Un controle indisponible n'est pas une penalite personnelle; contactez un officier si l'etat reste bloque.

Scope: `player` | Audit: `false` | Reason required: `false`

## Guild Dibs status

- **ID:** `player.status`
- **Category:** `setup`
- **Audience:** player

**English:** Explains whether your personal Dibs information is available. If features are limited or unavailable, retry later or contact an Officer; RCLootCouncil is optional and Standalone mode can remain available.
**Francais:** Indique si vos informations Dibs personnelles sont disponibles. Si certaines fonctions sont limitees ou indisponibles, reessayez plus tard ou contactez un officier; RCLootCouncil est optionnel et le mode Standalone peut rester disponible.

Scope: `guild` | Audit: `false` | Reason required: `false`

## Encounter Mode

- **ID:** `predibs.encounter.mode`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** Controls when players may submit a Pre-Dib. Encounter mode requires the matching raid and difficulty context; Wild Open may allow requests outside the raid under guild policy.
**Francais:** Determine quand les joueurs peuvent envoyer un Pre-Dib. Le mode Encounter exige le raid et la difficulte correspondants; Wild Open peut autoriser les demandes hors raid selon la politique de guilde.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Pre-Dib Request

- **ID:** `predibs.request`
- **Category:** `predibs`
- **Audience:** gm, officer, player

**English:** A Pre-Dib records your interest in eligible loot. It does not award an item or spend a Dib; that happens only after a qualifying award is finalized.
**Francais:** Un Pre-Dib indique votre interet pour un butin eligible. Il n'attribue pas l'objet et ne depense pas de Dib; cela arrive seulement apres un gain eligible finalise.

Scope: `guild-season` | Audit: `false` | Reason required: `false`

## Synchronization

- **ID:** `sync.status`
- **Category:** `synchronization`
- **Audience:** gm, officer, player

**English:** Shows whether this client can exchange current guild Dibs state. Unavailable or behind clients may be unable to apply canonical updates.
**Francais:** Indique si ce client peut echanger l'etat Dibs actuel de la guilde. Un client indisponible ou en retard peut ne pas appliquer les mises a jour canoniques.

Scope: `guild` | Audit: `false` | Reason required: `false`
