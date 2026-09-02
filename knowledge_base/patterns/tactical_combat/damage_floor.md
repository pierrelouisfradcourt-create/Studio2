# Pattern — Damage Floor (plancher de dégâts)

- **brick_id** : `pat-damage-floor`
- **kind** : pattern (advisory, cité — ZÉRO code repris)
- **source** : Battle for Wesnoth — mécaniques de combat
- **provenance_url** : https://wiki.wesnoth.org/CombatMechanics
- **licence** : GPL-2.0-or-later (concept cité uniquement ; aucune ligne de code Wesnoth n'est
  copiée ni distribuée — un pattern n'a pas de runtime)
- **runtime** : agnostic — **advisory_only: true**

## Énoncé

Tout coup porté inflige **au moins 1 point de dégât**, quelle que soit la défense :

```
dégât_effectif = max(1, dégât_brut − réduction)
```

## Pourquoi (invariant de conception)

Sans plancher, deux unités très défensives peuvent se frapper indéfiniment sans résultat
(`dégât_brut − réduction ≤ 0`) : l'affrontement **ne progresse jamais** → impasse (stalemate).
Le plancher garantit qu'un échange **fait toujours avancer l'état** vers une résolution.

## Invariants testables (à faire tenir chez tout système inspiré)

1. `dégât_effectif ≥ 1` pour tout couple (dégât_brut ≥ 0, réduction ≥ 0).
2. Monotonie : à réduction fixe, `dégât_brut` croissant ⇒ `dégât_effectif` croissant ou égal.
3. Déterminisme : mêmes entrées ⇒ même sortie (aucun aléa non injecté).

## Usage advisory

Cité en conception (s1/s2-worldscan) pour justifier une règle de combat anti-impasse. Le CODE
qui l'implémente vit dans `knowledge_base/systems/` sous licence permissive, en **réécriture
propre** — il ne peut PAS être importé depuis ce fichier (règle R11 du validateur).
