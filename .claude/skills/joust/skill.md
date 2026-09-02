---
name: joust
description: Joute — même tâche confiée à deux modèles en worktrees isolés, même oracle pour les deux, l'oracle tranche. Ambigu → gate Pierre.
---

# /joust

Quand une tâche admet plusieurs approches, on ne devine pas le meilleur modèle : on les fait concourir sur la **même** tâche, on les juge avec le **même** oracle non-LLM, et on garde le gagnant. L'oracle arbitre, jamais Claude.

> `claim_verdict: NO_CLAIM_ALLOWED` — le verdict vient de l'oracle, pas d'une appréciation de style.
> Caps studio : 200k tokens · 8 itérations par tâche (AGENTS.md).

---

## Phase 1 — Cadrer la joute

- **Énoncé unique** : la même spécification, le même write-scope, le même oracle pour A et B. Toute asymétrie invalide la comparaison.
- **Deux compétiteurs** : deux modèles/agents distincts (ex. `producteur_dur` Claude vs `producteur_routine` Qwen, ou deux modèles LM Studio).
- **Oracle défini d'avance** : la commande qui tranchera (cf. `/verdict` Phase 1) — `cargo test`, `pytest`, `elo_match`, `lichess_eval`. Choisi **avant** de lancer, pour éviter le biais.

Si la tâche n'a pas d'oracle mécanique → ce n'est pas une joute, c'est du fog → `/fog` puis gate Pierre.

---

## Phase 2 — Exécuter en worktrees isolés

Chaque compétiteur travaille dans son **propre git worktree** — aucune collision de fichiers, aucune contamination croisée.

```bash
git worktree add ../joust-A <branche-base>
git worktree add ../joust-B <branche-base>
```

- Agent A → `../joust-A`, agent B → `../joust-B`, même énoncé.
- Mêmes caps (200k tokens, 8 itérations) appliqués à chacun.
- `intention_racine` propagée à chaque agent (anti-Skynet).
- Zones FORBIDDEN (`tests/ eval/ oracle/ bench/ puzzles/ .github/`) interdites aux deux.

---

## Phase 3 — Juger : même oracle, deux fois

Lancer **le même** oracle sur chaque worktree, en sandbox hors write-scope. Récupérer les verdicts signés.

```
JOUST — <tâche> (oracle : <nom>)
─────────────────────────────────────────────
A (<modèle A>)  : software=<OK|FAIL>  oracle=<PASS|FAIL>  <métrique clé>  HMAC=<OK|…>
B (<modèle B>)  : software=<OK|FAIL>  oracle=<PASS|FAIL>  <métrique clé>  HMAC=<OK|…>
─────────────────────────────────────────────
```

Règle d'arbitrage (l'oracle tranche, dans l'ordre) :

1. Un seul `PASS` → **il gagne**.
2. Les deux `PASS` → départage par la **métrique de l'oracle** (delta ELO, % puzzles, nb tests, temps). Écart significatif → le meilleur gagne.
3. Les deux `FAIL` → **personne ne gagne** : aucune branche n'est mergée, rapport à Pierre.
4. Égalité ou écart non significatif → **ambigu** → gate Pierre.

---

## Phase 4 — Merge du gagnant (via gate)

```
→ gagnant : <A|B|AUCUN|AMBIGU>
→ <merge du gagnant via /gate | rollback des deux | escalade Pierre>
```

- Gagnant net → préparer le verdict (`/verdict`) puis présenter la gate (`/gate`) — Pierre ratifie le merge.
- Le worktree perdant et tout worktree non mergé sont supprimés :

```bash
git worktree remove ../joust-A   # perdant
git worktree remove ../joust-B   # après merge du gagnant
```

---

## Hard rules

- **Même oracle, même énoncé, même scope** pour A et B — sinon la joute est nulle.
- L'oracle tranche, jamais Claude. Ambigu ou double FAIL → gate Pierre, pas de choix arbitraire.
- Verdict d'un compétiteur sans HMAC valide → il ne peut pas gagner (non opposable).
- Ne jamais merger les deux branches ; une seule survit, via `/gate`.
- Nettoyer **tous** les worktrees en fin de joute — pas de worktree orphelin.
- Caps respectés par chaque compétiteur : 200k tokens / 8 itérations.

## Cas d'erreur

| Situation | Action |
|---|---|
| Pas d'oracle mécanique pour la tâche | Ce n'est pas une joute → `/fog` + gate Pierre |
| Un agent dépasse les caps | Disqualifié si l'autre a un `PASS` signé ; sinon double échec → Pierre |
| Worktree non nettoyé | `git worktree remove` ; `git worktree prune` si référence cassée |
| Les deux `FAIL` | Aucun merge, rollback des deux, rapport à Pierre |
| Verdicts ambigus / écart non significatif | Gate Pierre — ne pas trancher à la place de l'oracle |
