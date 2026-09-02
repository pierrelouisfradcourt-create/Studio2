---
name: fog
description: Carte de brouillard — lit studio_meta_latest.json et sépare ce qui est VÉRIFIÉ par oracle de ce qui relève du JUGEMENT humain (fog → Pierre).
---

# /fog

Cartographie l'état du studio en deux zones : **vérifié** (un oracle non-LLM a tranché) et **fog** (aucun oracle — décision Pierre). Le fog n'est pas une erreur, c'est la frontière honnête de ce que la machine sait prouver.

> Doctrine : *Fog = pas d'oracle → human_gate → Pierre* (SOUL.md coordinateur).
> `claim_verdict: NO_CLAIM_ALLOWED` — ce skill décrit, il ne conclut jamais.

---

## Phase 1 — Charger le snapshot le plus récent

`studio_meta_latest.json` peut exister à trois emplacements. Prendre **le plus récent par mtime** :

```
1. studio_meta_latest.json              (racine repo)
2. .studio_state/studio_meta_latest.json
3. lab/reports/studio_meta_latest.json
```

Si aucun n'existe → le régénérer :

```bash
python scripts/studio_meta.py lab/chains/IMPROVEMENT_LEDGER.yaml
```

Si la régénération échoue (exit ≠ 0) → escalader Pierre, ne pas inventer d'état. Bloqueur.

Vérifier que le `timestamp` du snapshot n'a pas plus de 24 h. Sinon, afficher un bandeau `⚠️ SNAPSHOT PÉRIMÉ (<âge>)` et proposer la régénération avant de continuer.

---

## Phase 2 — Zone VÉRIFIÉE (oracles)

Lire le bloc `oracles` du JSON. Chaque entrée a un `verdict` (`PASS`/`FAIL`/`BLOCKED`) tranché par un oracle non-LLM, donc **opposable**.

```
VÉRIFIÉ — oracles (snapshot <timestamp>)
─────────────────────────────────────────────
elo_match      <verdict>  delta hybride−heuristique = <delta>  (cible ≥ +20)
lichess_eval   <verdict>  L1 <pct>% / L2 <pct>% / L3 <pct>%   (seuils 80/10/20)
─────────────────────────────────────────────
ELO live    : heuristic <x> | hybrid <x> | neural <x>
global_verdict : <PASS|FAIL>
```

- `verdict: PASS` → ✅ prouvé.
- `verdict: FAIL` → ❌ prouvé négatif (c'est aussi de la vérité, pas du fog).
- `verdict: BLOCKED` ou `available: false` → l'oracle n'a pas pu statuer → bascule en **fog**.

---

## Phase 3 — Zone FOG (jugement humain)

Domaines **sans oracle** → décision Pierre. Référence : table Domaine→Oracle d'`AGENTS.md`.

| Domaine | Oracle | Statut |
|---|---|---|
| Engine Rust | cargo test + elo_match.sh | vérifiable |
| Neural / φ | training metrics + ELO | vérifiable |
| Tactique | lichess_eval.sh | vérifiable |
| Gameplay Godot | tests + le jeu tourne | vérifiable |
| Performance | cargo bench + profiler | vérifiable |
| **Narrative / UI / Audio** | **Pierre** | **FOG** |
| QA | cargo / pytest | vérifiable |

Ajouter au fog :
- les oracles `BLOCKED`/indisponibles de la Phase 2 ;
- les entrées de `blockers` du snapshot (ex. `φ pipeline NOT_STARTED`) ;
- tout IMP `OPEN` dont le domaine tombe dans une ligne FOG.

```
FOG — jugement requis (Pierre)
─────────────────────────────────────────────
🌫️ Narrative / UI / Audio        — aucun oracle, ressenti Pierre
🌫️ <blocker du snapshot>          — <raison>
🌫️ <oracle BLOCKED>              — l'oracle n'a pas tranché
─────────────────────────────────────────────
fog_score : N éléments hors-trace
```

`fog_score` = nombre d'éléments en zone fog. Score élevé = beaucoup de surface non prouvable → router vers human_gate.

---

## Sortie consolidée

```
🗺️  FOG MAP — <date>
═════════════════════════════════════════════
VÉRIFIÉ (oracle opposable) :
  ✅/❌ ...
FOG (décision Pierre) :
  🌫️ ...
─────────────────────────────────────────────
global_verdict : <PASS|FAIL>   ·   fog_score : N
═════════════════════════════════════════════
```

---

## Hard rules

- Ne **jamais** transformer un élément fog en verdict : pas d'oracle = pas de claim.
- Lecture seule : `/fog` ne modifie aucun fichier (sauf régénération explicite du snapshot via `studio_meta.py`).
- Un `FAIL` oracle reste en zone VÉRIFIÉE — c'est une vérité négative, pas du fog.
- Snapshot absent **et** `studio_meta.py` cassé → escalader Pierre, pas de workaround.

## Cas d'erreur

| Situation | Action |
|---|---|
| Aucun `studio_meta_latest.json` | Régénérer via `studio_meta.py` ; si échec → escalader |
| Snapshot > 24 h | Bandeau `⚠️ PÉRIMÉ`, proposer régénération |
| `oracles` absent du JSON | Tout passe en fog, signaler le snapshot incomplet |
| `IMPROVEMENT_LEDGER.yaml` absent | Bloqueur — escalader Pierre |
