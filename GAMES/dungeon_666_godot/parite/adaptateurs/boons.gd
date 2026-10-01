extends RefCounted
## Adaptateurs des vecteurs « boons » (src/sim/boons.mjs). Une bénédiction est désignée par son
## identifiant ; une partie par sa fiche.

const Outils := preload("res://parite/adaptateurs/state.gd")

static func _roll_boon_offer(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	var offer := D6Boons.roll_boon_offer(g, a[1])
	return {"offer": offer, "s": g.rng.gen.s}

static func _add_boon(a: Array) -> Array:
	var run := {"boons": D6Js.clone(a[0])}
	D6Boons.add_boon(run, D6Js.clone(a[1]))
	return run.boons

static func _random_family(a: Array) -> Array:
	var g := Outils.make_game(a[0])
	var out: Array = []
	for i in 8:
		out.append(D6Boons.random_family(g))
	return out

static func adapters() -> Dictionary:
	return {
		"boonDef": func(a): return D6Boons.boon_def(a[0]),
		"boonValue": func(a): return D6Boons.boon_value(D6Boons.boon_def(a[0]), a[1]),
		"boonText": func(a): return D6Boons.boon_text(D6Boons.boon_def(a[0]), a[1]),
		"rollBoonOffer": _roll_boon_offer,
		"addBoon": _add_boon,
		"randomFamily": _random_family,
	}
