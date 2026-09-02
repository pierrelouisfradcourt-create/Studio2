---
name: reanchor
description: Recalibrer les ancres Lichess — relance lichess_eval.sh et met à jour MEMORY.md avec les nouveaux seuils datés.
---

# /reanchor

Recalibration des ancres de performance tactique. À lancer après chaque changement significatif du moteur ou une fois par semaine.

---

## Phase 1 — Lancement bench

```bash
./bench/lichess_eval.sh
```

Si exit ≠ 0 → afficher l'erreur, stopper. Ne pas mettre à jour MEMORY.md sur un bench rouge.

---

## Phase 2 — Lecture des résultats

Extraire depuis la sortie :

| Niveau | Résultat | Seuil cible |
|---|---|---|
| L1 | <score%> | ≥ 80% |
| L2 | <score%> | ≥ 10% |
| L3 | <score%> | ≥ 20% |

Afficher :

```
REANCHOR — résultats lichess_eval.sh (<date>)
─────────────────────────────────────────────
L1 : <score>%  [<PASS|FAIL> — seuil 80%]
L2 : <score>%  [<PASS|FAIL> — seuil 10%]
L3 : <score>%  [<PASS|FAIL> — seuil 20%]
─────────────────────────────────────────────
Verdict global : <PASS|FAIL>
```

---

## Phase 3 — Mise à jour MEMORY.md

Mettre à jour la section `## Ancres` de `studio/openclaw-workspace/MEMORY.md` :

```markdown
- Lichess puzzles : lab/puzzles/level1-3.jsonl + holdout_level1-3.jsonl (CC0)
  · L1 <score>% <PASS|FAIL> / L2 <score>% <PASS|FAIL> / L3 <score>% <PASS|FAIL>
  · Seuils cibles : L1≥80% / L2≥10% / L3≥20%
  · last run <date>
- Dernier /reanchor : <date>
```

Ne jamais écraser une ancre PASS avec un résultat FAIL sans gate Pierre explicite.

---

## Hard rules

- bench rouge → STOP, pas de mise à jour MEMORY.md.
- Ancre PASS → FAIL : escalader Pierre avant d'écrire.
- Ne jamais modifier `bench/lichess_eval.sh` (zone FORBIDDEN).
- Lancer depuis la racine du repo (`./bench/lichess_eval.sh`, pas depuis `bench/`).
