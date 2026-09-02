---
name: smoke-check
description: Gate oracle 4-en-1 TCS (cargo test + pytest ml/ + elo_match + lichess_eval) — un seul FAIL arrête tout, merge interdit sans PASS consolidé.
---

# /smoke-check

Lance les quatre oracles non-LLM de TCS dans l'ordre. Chaque oracle est **mécanique** (exit code / JSON signé) : aucun agent ne peut substituer son jugement au résultat brut. Un seul FAIL suffit pour bloquer le merge — pas de compensation, pas d'exception.

> Règles absolues (CLAUDE.md) : `claim_verdict: NO_CLAIM_ALLOWED`, séparer `software_verdict` / `evidence_verdict` / `claim_verdict`, HumanGate décide le merge (`/gate`). Zones FORBIDDEN (ne jamais modifier pour faire passer un verdict) : `bench/`, `tests/`, `eval/`, `oracle/`, `puzzles/`, `.github/`.

---

## Étape 1 — Moteur Rust : `cargo test --release`

```bash
cargo test --release
```

Oracle : exit code.
- Exit 0 → step PASS
- Exit ≠ 0 → **verdict global FAIL → STOP**. Ne pas lancer les étapes suivantes.

> Couvre compilation + suite de tests unitaires/intégration Rust (`src/chess/`). Le flag `--release` garantit que les optimisations ne masquent pas de comportement debug-only.

---

## Étape 2 — Suite Python ML : `.venv312\Scripts\python.exe -m pytest ml/ -v`

```bash
.venv312\Scripts\python.exe -m pytest ml/ -v
```

Oracle : exit code pytest.
- Exit 0 → step PASS
- Exit ≠ 0 → **verdict global FAIL → STOP**.

> Ne pas utiliser `python` système — le venv `.venv312` est le seul environnement garanti avec les dépendances ML correctes. Un dataset `BROKEN` est bloqueur P4 (cf. `.claude/rules/python-ml.md`).

---

## Étape 3 — Match ELO : `./scripts/run_oracle.sh elo_match`

```bash
./scripts/run_oracle.sh elo_match
```

Chemin canonique (wrapper backbone). Appelle `./bench/elo_match.sh` (zone FORBIDDEN) puis ingère le rapport via `ingest_event.py`. Rapport produit : `lab/reports/elo_match_latest.json` + `lab/reports/elo_match_latest.json.hmac`.

> Note : la commande directe `./bench/elo_match.sh` fonctionne en stand-alone mais ne déclenche pas l'ingestion backbone — toujours préférer le wrapper `run_oracle.sh`.

Oracle : `verdict` dans le JSON + HMAC.

**Vérifier la signature avant d'y croire :**

```bash
EXPECTED=$(openssl dgst -sha256 -hmac "$STUDIO_HMAC_KEY" \
  lab/reports/elo_match_latest.json | awk '{print $NF}')
ACTUAL=$(awk '{print $NF}' lab/reports/elo_match_latest.json.hmac)
[ "$EXPECTED" = "$ACTUAL" ] && echo "HMAC OK" || echo "HMAC INVALIDE — STOP"
```

- JSON `verdict: PASS` **et** HMAC OK → step PASS
- JSON `verdict: FAIL` **ou** HMAC invalide → **verdict global FAIL → STOP**
- `STUDIO_HMAC_KEY` absent → rapport non signé → `evidence_verdict: UNSIGNED`, escalader Pierre

---

## Étape 4 — Tactique Lichess : `./scripts/run_oracle.sh lichess_eval`

```bash
./scripts/run_oracle.sh lichess_eval
```

Chemin canonique (wrapper backbone). Appelle `./bench/lichess_eval.sh` (zone FORBIDDEN) puis ingère le rapport. Rapport produit : `lab/reports/lichess_eval_latest.json` + `lab/reports/lichess_eval_latest.json.hmac`.

Oracle : `verdict` dans le JSON + HMAC (même protocole que l'étape 3).

```bash
EXPECTED=$(openssl dgst -sha256 -hmac "$STUDIO_HMAC_KEY" \
  lab/reports/lichess_eval_latest.json | awk '{print $NF}')
ACTUAL=$(awk '{print $NF}' lab/reports/lichess_eval_latest.json.hmac)
[ "$EXPECTED" = "$ACTUAL" ] && echo "HMAC OK" || echo "HMAC INVALIDE — STOP"
```

- JSON `verdict: PASS` **et** HMAC OK → step PASS
- JSON `verdict: FAIL` **ou** HMAC invalide → **verdict global FAIL → STOP**

---

## Rapport consolidé

Émettre ce bloc après les quatre étapes (ou dès qu'un FAIL interrompt la séquence) :

```
SMOKE-CHECK — <timestamp ISO>
══════════════════════════════════════════════════
Étape 1  cargo test --release          : <PASS|FAIL>
Étape 2  pytest ml/                    : <PASS|FAIL>
Étape 3  elo_match   (HMAC: <OK|KO>)  : <PASS|FAIL>
Étape 4  lichess_eval (HMAC: <OK|KO>) : <PASS|FAIL>
──────────────────────────────────────────────────
Verdict global                         : <PASS|FAIL|BLOCKED>

software_verdict : <OK|FAIL|BLOCKED>
evidence_verdict : <MECHANICAL_VALIDATION_ONLY|UNSIGNED>
claim_verdict    : NO_CLAIM_ALLOWED
──────────────────────────────────────────────────
→ merge éligible : <OUI si toutes étapes PASS + tous HMAC OK | NON>
   (ratification finale = Pierre via /gate)
```

---

## Hard rules

- Tout FAIL à n'importe quelle étape → **stop immédiat**, `software_verdict: FAIL`, pas de merge.
- HMAC invalide ou absent → **stop**, escalader Pierre. Jamais merger sur un rapport non signé.
- L'agent ne décide **jamais** le merge — il produit le bloc verdict, Pierre tranche (`/gate`).
- Ne jamais modifier `bench/`, `tests/`, `eval/`, `oracle/` pour faire passer un verdict.
- « J'ai lancé X » ≠ « X est PASS » : montrer la sortie brute de l'oracle, pas une paraphrase.

## Cas d'erreur

| Situation | Action |
|---|---|
| `STUDIO_HMAC_KEY` non défini | Rapport non signé → `evidence_verdict: UNSIGNED`, escalader Pierre |
| `openssl` absent | Stop — vérification HMAC impossible, escalader Pierre |
| Rapport JSON absent après oracle | L'oracle a échoué en amont → lire le `.log`, rapporter, ne pas merger |
| `.hmac` ≠ recalcul | Altération détectée → stop immédiat, alerte Pierre |
| oracle `BLOCKED` | `software_verdict: BLOCKED` — ni merge ni rejet, escalader Pierre |
| Réseau indisponible pour lichess_eval | `software_verdict: BLOCKED` — ne pas simuler le verdict, escalader Pierre |
