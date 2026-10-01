extends RefCounted
## Adaptateurs des vecteurs « physics » (src/sim/physics.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

static func _move_circle(a: Array) -> Dictionary:
	var ent: Dictionary = a[1].duplicate()
	var res: Dictionary = D6Physics.move_circle(a[0], ent, a[2], a[3])
	return {"hitWall": res.hitWall, "nx": res.nx, "ny": res.ny, "x": ent.x, "y": ent.y}

static func adapters() -> Dictionary:
	return {
		"roomBounds": func(a): return D6Physics.room_bounds(a[0]),
		"moveCircle": _move_circle,
		"pointBlocked": func(a): return D6Physics.point_blocked(a[0], a[1], a[2], a[3]),
		"lineOfSight": func(a): return D6Physics.line_of_sight(a[0], a[1], a[2], a[3], a[4]),
	}
