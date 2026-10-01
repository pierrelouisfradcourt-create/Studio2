extends RefCounted
## Adaptateurs des vecteurs « geo » (src/core/math.mjs) : pour chaque fonction exportée par la simulation
## web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

static func _out(f: Callable, a: Array) -> Dictionary:
	var out := {"x": 0.0, "y": 0.0, "nx": 0.0, "ny": 0.0}
	var ret = f.callv([out] + a)
	if ret is Dictionary:
		ret = {"x": out.x, "y": out.y, "nx": out.nx, "ny": out.ny} # closestOnRect rend `out` lui-même
	return {"ret": ret, "x": out.x, "y": out.y, "nx": out.nx, "ny": out.ny}

static func adapters() -> Dictionary:
	var direct := {
		"clamp": D6Geo.clampv, "lerp": D6Geo.lerpv, "len": D6Geo.length, "dist": D6Geo.dist, "dist2": D6Geo.dist2,
		"approach": D6Geo.approach, "angleDiff": D6Geo.angle_diff, "inSector": D6Geo.in_sector,
		"circlesOverlap": D6Geo.circles_overlap, "pointSegDist2": D6Geo.point_seg_dist2,
		"pointBandDist2": D6Geo.point_band_dist2, "easeOutCubic": D6Geo.ease_out_cubic, "easeInQuad": D6Geo.ease_in_quad,
	}
	var out := {}
	for k in direct:
		var f: Callable = direct[k]
		out[k] = func(a): return f.callv(a)
	out["normalizeInto"] = func(a): return _out(D6Geo.normalize_into, a)
	out["closestOnRect"] = func(a): return _out(D6Geo.closest_on_rect, a)
	out["pushCircleOutOfRect"] = func(a): return _out(D6Geo.push_circle_out_of_rect, a)
	out["pushCircleOutOfCircle"] = func(a): return _out(D6Geo.push_circle_out_of_circle, a)
	return out
