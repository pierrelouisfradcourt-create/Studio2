# ÉTAT FACTUEL DU STUDIO — auto-généré (ne pas éditer à la main)

> ⚠ Fichier **AUTO-GÉNÉRÉ** par `node scripts/forge/studio_selfaudit.mjs --write`. Relu du
> disque, pas écrit à la main → il ne peut PAS se périmer. Les cartes de référence
> (STUDIO_ARCHITECTURE · STUDIO_AGENT_ATLAS · STUDIO_MASTER_SCHEMA) citent ce fichier pour
> la partie « qui existe » ; leur prose (le POURQUOI) reste humaine. `claim_verdict: NO_CLAIM_ALLOWED`.

## Éléments suivis — ce que les cartes affirment vs la réalité disque

| Élément | Carte affirme | Réalité | Statut |
|---|---|---|---|
| `knowledge_base/search.mjs` | existe | ✅ présent | aligné |
| `knowledge_base/role_sim.mjs` | existe | ✅ présent | aligné |
| `scripts/forge/reuse_ratio.mjs` | existe | ✅ présent | aligné |
| `scripts/forge/pool.py` | existe | ✅ présent | aligné |
| `scripts/forge/contracts/s2.5-artbible.yaml` | existe | ✅ présent | aligné |
| `knowledge_base/roles/pursuer-mobile.yaml` | existe | ✅ présent | aligné |
| `scripts/forge/agents_ccgs` | cible (à construire) | ⬜ absent | aligné (encore à construire) |

## Connecteurs propose-only — fraîcheur (retard sur la télémétrie)

| Connecteur | État |
|---|---|
| `lab/reports/forge_ledger_proposals.jsonl` | ✅ frais |
| `lab/reports/forge_project_proposals.jsonl` | ✅ frais |
| `lab/reports/forge_bible_proposals.jsonl` | ✅ frais |
| `knowledge_base/learning_curve.jsonl` | ✅ frais |

## Contrat de système Forge — règles canoniques citées par le pilotage

| Règle | Symboles attendus | Verdict |
|---|---|---|
| *(toutes les règles canoniques)* | — | ✅ synchronisé (mécaniquement) |

**Verdict global** : ✅ ALIGNÉ (dérive doc : 0 · connecteurs dormants : 0 · contrat de système : ok)

