---
name: league
description: Match ELO Rocky vs panel (heuristic / hybrid / neural / teacher_uci). Seuil hybride − heuristique ≥ +20, sinon « neural pas encore utile ».
---

# /league

Fait jouer Rocky contre son panel d'agents et lit le verdict ELO. Le panel mesure si l'apport neural est réel : tant que l'hybride ne dépasse pas l'heuristique de +20 ELO, le réseau ne paie pas son coût.

> Oracle FORBIDDEN : `bench/elo_match.sh` DÉCIDE. Ne jamais le modifier.
> `claim_verdict: NO_CLAIM_ALLOWED` — on rapporte les ratings, on n'extrapole pas.

---

## Phase 1 — Lancer le tournoi

```bash
./scripts/run_oracle.sh elo_match --games 50
```

`run_oracle.sh` enchaîne `bench/elo_match.sh` (build release + `neural_tournament`) puis l'ingest backbone. Sortie signée : `lab/reports/elo_match_latest.json` (+ `.hmac`).

- `--games N` : 20 par défaut. ≥ 50 pour une mesure stable, moins pour un check rapide.
- 35k+ lignes de traces partent dans `lab/reports/elo_match_run.log` — ne lire que le rapport JSON.

Si exit ≠ 0 → lire la fin du `.log`, rapporter l'erreur, **ne pas** interpréter de ratings partiels.

---

## Phase 2 — Lire le panel

Le panel est dans `ratings` du JSON. Agents attendus :

| Agent | Rôle | Baseline observée |
|---|---|---|
| `teacher_uci` | plafond (moteur UCI prof) | ~1386 |
| `hybrid` | Rocky heuristique + neural | ~1195–1212 |
| `heuristic` | Rocky pur heuristique | ~1176–1202 |
| `neural` | réseau seul | ~990–1001 |

Métrique de décision (calculée par l'oracle, champ `delta_hybrid_vs_heuristic`) :

```
delta = hybrid − heuristic        cible ≥ +20  →  verdict PASS
```

---

## Phase 3 — Affichage

```
LEAGUE — match ELO (<timestamp>, games=<N>)
─────────────────────────────────────────────
teacher_uci  <elo>      (plafond)
hybrid       <elo>
heuristic    <elo>
neural       <elo>
─────────────────────────────────────────────
delta hybride − heuristique : <delta>   (cible ≥ +20)
verdict oracle : <PASS|FAIL|BLOCKED>   (reason : <reason>)
```

Lecture :

- `delta ≥ +20` → ✅ le neural apporte un gain net.
- `0 ≤ delta < +20` → ⚠️ flag **« neural pas encore utile »** : l'hybride n'amortit pas le réseau.
- `delta < 0` → ❌ le neural **dégrade** l'heuristique → régression, alerter.
- `neural` proche de 1000 et très en-dessous de `heuristic` → normal en l'état (φ pipeline `NOT_STARTED`), à ne pas confondre avec un bug.

---

## Phase 4 — Vérifier la signature

Avant de citer le verdict comme opposable, vérifier le HMAC (cf. `/verdict` Phase 2) :

```bash
openssl dgst -sha256 -hmac "$STUDIO_HMAC_KEY" lab/reports/elo_match_latest.json | awk '{print $NF}'
awk '{print $NF}' lab/reports/elo_match_latest.json.hmac
```

Égaux → verdict signé. `STUDIO_HMAC_KEY` absent → ratings indicatifs seulement, le signaler.

---

## Hard rules

- Ne **jamais** modifier `bench/elo_match.sh` ni le seuil +20 (zone FORBIDDEN).
- Lancer depuis la racine du repo (`./scripts/run_oracle.sh ...`).
- Ratings sans HMAC valide = indicatifs, **pas** opposables pour un merge.
- Régression `delta < 0` → ne pas merger le changement neural, escalader Pierre.
- Ne pas relancer en boucle pour « avoir un meilleur chiffre » : un seul run signé fait foi.

## Cas d'erreur

| Situation | Action |
|---|---|
| Binaire exit ≠ 0 | Lire `lab/reports/elo_match_run.log` (tail), rapporter, pas de ratings |
| `elo.csv` absent | Le tournoi n'a pas abouti — vérifier `TCS_EXPERIMENT_ID`, rapporter |
| `heuristic` ou `hybrid` manquant | verdict `BLOCKED` — panel incomplet, escalader |
| Step python3 du bench échoue (stub Windows) | `run_oracle.sh` injecte un shim ; sinon définir `TCS_PYTHON_EXE` |
| `STUDIO_HMAC_KEY` absent | Rapport non signé — ratings indicatifs, le signaler |
