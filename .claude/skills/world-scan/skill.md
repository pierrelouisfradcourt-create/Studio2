---
name: world-scan
description: World Intelligence Layer (Phase 5) — recherche web citée de patterns externes comparables pour un IMP donné, produit un knowledge packet JSON advisory-only lu en lecture seule par le board. N'injecte JAMAIS dans les prompts council.
---

# /world-scan <IMP-ID>

Étant donné un IMP, cherche des patterns externes comparables (projets open-source,
postmortems, articles d'architecture, wikis techniques) et produit un **knowledge packet
JSON cité**, consultable dans le panneau détail du board.

Le packet **informe, il ne tranche jamais**. Il n'est **jamais** injecté automatiquement
dans les prompts du council (council-audit / arbitration) — ce serait une extension
ultérieure explicite, hors scope de cette skill.

Le moteur graphe llm-lego est offline (LM Studio / Qwen local uniquement) et n'a aucun
accès web. Cette skill tourne côté Claude Code (WebSearch / WebFetch) — mécanisme séparé,
déclenché à la demande sur un IMP précis.

---

## Pré-conditions

- `IMP-ID` fourni et présent dans `lab/chains/IMPROVEMENT_LEDGER.yaml` — sinon stopper.
- Lecture du ledger en **lecture seule** (contexte de l'IMP uniquement). Aucune écriture ledger.

---

## Phase 1 — Contexte IMP (read-only)

Lire le bloc de l'IMP dans `lab/chains/IMPROVEMENT_LEDGER.yaml`. Extraire :
`title`, `type`, `theme`, `domain`, `files`, `acceptance`, et l'essence technique des `notes`.
Ne rien écrire dans le ledger.

## Phase 2 — Formuler les requêtes

Dériver 2 à 4 requêtes de recherche ciblant des patterns externes **comparables** au
problème de l'IMP (pas des reformulations du titre). Viser : implémentations open-source,
postmortems, décisions d'architecture, wikis/références techniques reconnus.

## Phase 3 — Recherche + lecture

Pour chaque requête : `WebSearch`, puis `WebFetch` sur 1–3 sources pertinentes pour lire
le contenu réel. **Ne jamais** rapporter un pattern à partir du seul titre de résultat —
lire la source avant de citer.

## Phase 4 — Structurer le knowledge packet

Écrire `llm-lego/knowledge/<IMP-ID>.json` (encoding utf-8, chemin repo-relatif),
au contrat **world-scan/v0** :

```json
{
  "schema": "world-scan/v0",
  "imp": "IMP-230",
  "imp_title": "<titre de l'IMP>",
  "generated_ts": "<ISO-8601 UTC>",
  "source_tool": "claude-code/websearch",
  "advisory_only": true,
  "no_decision": "Ce packet informe, il ne tranche pas. Aucune action de design declenchee.",
  "queries": ["<requête 1>", "<requête 2>"],
  "patterns": [
    {
      "claim": "<résumé court reformulé, ≤ 600 caractères, jamais une copie longue>",
      "source_url": "https://…",
      "source_title": "<titre de la source>",
      "accessed_ts": "<YYYY-MM-DD>",
      "relevance_note": "<pourquoi c'est pertinent pour CET IMP>"
    }
  ],
  "caveats": "<limites : sources partielles, non vérifiées contradictoirement, etc.>"
}
```

Règles de contenu **dures** (le validateur `knowledge-validate.mjs` les rejette) :
- `advisory_only` DOIT être `true`.
- `patterns` DOIT être non vide, et **chaque** pattern DOIT avoir un `source_url` http(s) valide
  et un `source_title` non vide. Aucune affirmation non attribuée.
- `claim` : résumé **court et reformulé** (≤ 600 caractères). Jamais de copie longue d'un texte source.
- `queries` non vide.

## Phase 5 — Rendu

Afficher à l'écran : le JSON produit + un rappel « advisory-only, n'influence pas le council ».
Ne rien décider. Si un pattern suggère un changement d'architecture, c'est une **proposition
affichée**, jamais une action.

---

## Comportements évidents (traités dès le départ)

- IMP absent du ledger → stop propre, pas de fichier écrit.
- Aucune source pertinente trouvée → ne PAS inventer ; écrire `patterns: []`… **non** : le contrat
  exige `patterns` non vide. Si vraiment rien : ne pas écrire de packet, rapporter « aucun pattern
  externe fiable trouvé » à l'écran.
- Source inaccessible (WebFetch échoue / redirection cross-host) → réessayer l'URL de redirection,
  sinon écarter la source. Ne jamais citer une URL non lue.
- Encoding utf-8 explicite. Chemin repo-relatif. Jamais de path absolu.

## Ce qui casse en premier (protection avant happy path)

Un pattern rapporté **sans source**, ou une **copie longue** d'un texte source.
→ Protection : citation obligatoire par pattern + `claim` plafonné ≤ 600 caractères,
imposés par le contrat et vérifiés par `knowledge-validate.mjs` avant toute confiance dans le packet.

## Hard rules

- Read-only strict : ledger, gate log, `tests/`, zones FORBIDDEN — jamais touchés.
- `llm-lego/knowledge/` est un dossier **non gouverné** (gitignored). Seule écriture autorisée : le packet.
- Jamais d'injection du packet dans les prompts council. Jamais de décision de design automatique.
- Citations obligatoires et sourcées. Résumés courts reformulés, jamais de copie longue.
- Rapport de fin : `software_verdict` / `evidence_verdict: MECHANICAL_VALIDATION_ONLY` / `claim_verdict: NO_CLAIM_ALLOWED`.
