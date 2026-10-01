extends RefCounted
## Adaptateurs des vecteurs « aim » (src/sim/aim.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

static func _compute_aim(a: Array) -> Dictionary:
	var o: Dictionary = D6Aim.compute_aim(a[0], a[1], a[2], a[3])
	return {"x": o.x, "y": o.y, "targetId": o.targetId, "targetDist": o.targetDist}

static func adapters() -> Dictionary:
	return {"computeAim": _compute_aim}
