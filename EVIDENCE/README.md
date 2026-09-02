# EVIDENCE — surface de preuve du Studio V2

Preuves et journaux produits par la Forge. **Hors de tout `run_dir`** : c'est la garantie
d'emplacement de la décision **J1** — un journal placé dans le corpus d'un run ferait trouver la
référence d'un message *par construction*, et `knowledge_trace --verify` rendrait un `FOUND` qui ne
prouve rien.

| dossier | contenu | producteur |
|---|---|---|
| `amendments/` | `journal.jsonl` — messages append-only (`question` · `objection` · `amendment`) | `forge.amendment_log` / `forge.emitter`, geste d'orchestrateur |

**Append-only** : une objection rejetée est conservée, jamais effacée.
**Propose-only** (R7) : aucune écriture durable ratifiée sans HumanGate.
