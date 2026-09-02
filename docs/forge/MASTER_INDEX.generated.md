# MASTER INDEX — sources de vérité de la mémoire du studio (auto-généré)

> ⚠ Fichier **AUTO-GÉNÉRÉ depuis `STUDIO_AGENT_ATLAS.md` §3, ne pas éditer.**
> Produit par `node scripts/forge/master_index.mjs --write`. La colonne « Existe »
> est relue du disque (`fs.existsSync`) → ce tableau ne peut PAS se périmer en silence.
> Chemins réduits au préfixe littéral (globs/placeholders `{..}` `<projet>` `*` ignorés).
> Déterministe, non-LLM, sans horodatage. `claim_verdict: NO_CLAIM_ALLOWED`.

| Source de vérité | Qui écrit | Nature | Existe | Règle |
|---|---|---|---|---|
| `knowledge_base/catalog.json` | agents design (tier candidate, propose) ; validateur admet | index bibliothèque | ✅ présent | validated = preuve d'un jeu gaté vert |
| `lab/chains/IMPROVEMENT_LEDGER.yaml` | via kaizen_loop.py ; Forge propose (propose_ledger_entry) | ledger canonique | ✅ présent | écriture durable = HumanGate ; settings.json Write(lab/chains/**) en *ask* |
| `lab/forge_evidence/*.log,*.jsonl` | oracles + connecteur télémétrie | preuves + tokens/durée | ✅ présent | evidence relue par verify_run |
| `lab/forge_runs/<projet>/{state.json,verdict.json,artifacts/}` | driver + oracles | état + verdict signé | ✅ présent | atomique, reprise après kill |
| `lab/forge_sensors/<jeu>/visual_mechanical.json` | s10d capteur | advisory visuel | ✅ présent | hors promotion |
| `lab/reports/forge_*.jsonl` | connecteurs 4/5/6 (propose-only) | propositions + journal PILOU | ✅ présent | jamais de mémoire de référence sans HumanGate |
| `llm-lego/knowledge/<IMP>.json` | world-scan (s2 / /world-scan) | knowledge packet web | ⬜ absent | gitignored, non gouverné, advisory-only |
| `memory/` | mécanisme auto-mémoire (Claude Code) | faits durables | ⬜ absent | jamais un agent Forge ; jamais dupliqué à la main |
| `studio_brain/00_CURRENT_CONTEXT.md` | Claude Code / Pierre | handoff inter-sessions | ✅ présent | < 100 lignes, archive dans journal/ |
| `studio_brain/{doctrine,decisions,...}` | Pierre (ratifié) | doctrine/vision (tier-2) | ✅ présent | décisions = ce que Pierre a ratifié |

**Sources suivies** : 10 · **absentes du disque** : 2 ⚠ (dérive doc↔réalité — corriger la carte ou ratifier)

- ⚠ `llm-lego/knowledge/<IMP>.json` (préfixe testé : `llm-lego/knowledge`) — cité par l'ATLAS §3 mais ABSENT du disque.
- ⚠ `memory/` (préfixe testé : `memory`) — cité par l'ATLAS §3 mais ABSENT du disque.

