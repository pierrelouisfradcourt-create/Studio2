extends RefCounted
## Adaptateurs des vecteurs « stats » (src/sim/stats.mjs) : recomputeStats sur des parties
## synthétiques (fiche : tuning, meta, run, héros). Sortie : le héros après le calcul, le kit
## résolu et l'arme active.

const Outils := preload("res://parite/adaptateurs/state.gd")

static func _recompute_stats(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	D6Stats.recompute_stats(g)
	return {"player": g.player, "kit": g.kit, "weapon": g.tuning.weapon.name}

static func adapters() -> Dictionary:
	return {"recomputeStats": _recompute_stats}
