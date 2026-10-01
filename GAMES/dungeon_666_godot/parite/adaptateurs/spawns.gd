extends RefCounted
## Adaptateurs des vecteurs « spawns » (src/sim/spawns.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

## args : [graine, salle, héros, apparitions en attente, r, minPlayerDist, near]. Rend le point
## trouvé ET l'état du générateur : l'ordre et le nombre des tirages font partie du contrat.
static func _find_spawn_point(a: Array) -> Dictionary:
	var game := {"room": a[1], "player": a[2], "spawns": a[3], "rng": {"gen": D6Rng.create_rng(a[0])}}
	var pt = D6Spawns.find_spawn_point(game, a[4], a[5], a[6])
	return {"pt": pt, "s": game.rng.gen.s}

static func adapters() -> Dictionary:
	return {"findSpawnPoint": _find_spawn_point}
