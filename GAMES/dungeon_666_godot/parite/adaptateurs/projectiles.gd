extends RefCounted
## Adaptateurs des vecteurs « projectiles » (src/sim/projectiles.mjs) : pour chaque fonction exportée par
## la simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

static func _compact(a: Array) -> Array:
	var arr: Array = a[0].duplicate()
	D6Projectiles.compact(arr)
	return arr

static func adapters() -> Dictionary:
	return {
		"hazardProgress": func(a): return D6Projectiles.hazard_progress(a[0]),
		"lingerLeft": func(a): return D6Projectiles.linger_left(a[0]),
		"compact": _compact,
		# Le même interprète de scénarios que combat : projectiles et zones sur plusieurs images.
		"scenario": load("res://parite/adaptateurs/combat.gd").scenario,
	}
