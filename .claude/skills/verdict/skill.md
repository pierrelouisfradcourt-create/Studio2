---
name: verdict
description: Verdict typé adossé à un oracle non-LLM + signature HMAC. software/evidence/claim séparés, NO_CLAIM_ALLOWED. FAIL ou HMAC invalide → stop.
---

# /verdict

Produit un verdict **opposable** : un oracle non-LLM tranche, le résultat est signé HMAC, et le verdict est typé en trois couches qui ne se mélangent jamais. Un agent peut RECOMMANDER ; seuls l'oracle + la signature font foi.

> Règles absolues (CLAUDE.md) : `claim_verdict: NO_CLAIM_ALLOWED`, séparer `software_verdict` / `evidence_verdict` / `claim_verdict`, HumanGate décide le merge.

---

## Phase 1 — Choisir l'oracle du domaine

| Domaine | Oracle (commande) | Rapport signé |
|---|---|---|
| Engine Rust | `cargo test --release` | exit code |
| ELO / neural | `./scripts/run_oracle.sh elo_match --games N` | `lab/reports/elo_match_latest.json` |
| Tactique | `./scripts/run_oracle.sh lichess_eval` | `lab/reports/lichess_eval_latest.json` |
| ML / Python | `.venv312\Scripts\python.exe -m pytest <path> -v` | exit code |

Lancer l'oracle **dans un sandbox hors write-scope** : l'agent qui exécute ne doit pas pouvoir éditer le code testé ni l'oracle lui-même. Zones FORBIDDEN (jamais modifiées par un agent) :

```
tests/  eval/  oracle/  bench/  puzzles/  .github/
```

`run_oracle.sh` appelle le bench FORBIDDEN puis ingère le rapport dans le backbone (`ingest_event.py`) — c'est le chemin câblé, ne pas réimplémenter.

---

## Phase 2 — Signature HMAC

Les benches signent automatiquement si `STUDIO_HMAC_KEY` est présent :

```bash
openssl dgst -sha256 -hmac "$STUDIO_HMAC_KEY" lab/reports/elo_match_latest.json \
  > lab/reports/elo_match_latest.json.hmac
```

**Vérifier la signature avant d'y croire** :

```bash
EXPECTED=$(openssl dgst -sha256 -hmac "$STUDIO_HMAC_KEY" lab/reports/<report>.json | awk '{print $NF}')
ACTUAL=$(awk '{print $NF}' lab/reports/<report>.json.hmac)
[ "$EXPECTED" = "$ACTUAL" ] && echo "HMAC OK" || echo "HMAC INVALIDE — STOP"
```

- `STUDIO_HMAC_KEY` absent → le rapport sort **non signé** (le bench le signale par `WARN`). Un verdict non signé n'est **pas** opposable → `evidence_verdict: UNSIGNED`, escalader Pierre.
- `.hmac` ≠ recalcul → rapport altéré ou clé différente → **stop immédiat**, ne pas merger.

---

## Phase 3 — Verdict typé (trois couches)

Émettre les trois, jamais fusionnées :

```
software_verdict : OK | FAIL | BLOCKED      ← le code compile/tourne ?
evidence_verdict : MECHANICAL_VALIDATION_ONLY | UNSIGNED   ← preuve d'exécution signée ?
claim_verdict    : NO_CLAIM_ALLOWED         ← toujours. Aucune extrapolation.
```

- `software_verdict` reflète l'oracle (exit 0 / `verdict: PASS` du JSON).
- `evidence_verdict` = `MECHANICAL_VALIDATION_ONLY` **seulement si** HMAC vérifié OK ; sinon `UNSIGNED`.
- `claim_verdict` = `NO_CLAIM_ALLOWED` en toute circonstance — preuve d'exécution, jamais preuve de qualité ou de sens.

---

## Phase 4 — Décision merge

```
VERDICT — <oracle> (<timestamp du rapport>)
─────────────────────────────────────────────
oracle           : <PASS|FAIL|BLOCKED>  (<reason du JSON>)
HMAC             : <OK|INVALIDE|NON_SIGNÉ>
software_verdict : <OK|FAIL|BLOCKED>
evidence_verdict : <MECHANICAL_VALIDATION_ONLY|UNSIGNED>
claim_verdict    : NO_CLAIM_ALLOWED
─────────────────────────────────────────────
→ merge éligible : <OUI si oracle PASS + HMAC OK | NON>
   (ratification finale = Pierre via /gate)
```

Merge **structurel** = oracle vert **ET** HMAC valide **ET** ratification Pierre (`/gate`). Les deux premières conditions sont nécessaires ; la troisième est souveraine.

---

## Hard rules

- `software_verdict: FAIL` → **stop**. Pas de merge, pas de gate.
- HMAC invalide ou absent → **stop**, escalader Pierre. Jamais merger sur un verdict non signé.
- L'agent ne décide **jamais** le merge — il prépare le verdict, Pierre tranche (`/gate`).
- Ne jamais modifier l'oracle (`bench/`, `tests/`, `eval/`, `oracle/`) pour faire passer un verdict.
- « J'ai implémenté X » ≠ « X fonctionne » : montrer la preuve d'exécution, pas la preuve d'existence.

## Cas d'erreur

| Situation | Action |
|---|---|
| `STUDIO_HMAC_KEY` non défini | Rapport non signé → `evidence_verdict: UNSIGNED`, escalader Pierre |
| `openssl` absent | Stop — pas de vérif possible, escalader |
| Rapport JSON absent après oracle | L'oracle a échoué en amont → lire le `.log`, rapporter, ne pas merger |
| `.hmac` ≠ recalcul | Altération → stop, alerte Pierre |
| oracle `BLOCKED` | `software_verdict: BLOCKED` — ni merge ni rejet, escalader Pierre |
