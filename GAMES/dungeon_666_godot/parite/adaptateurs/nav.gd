extends RefCounted
## Adaptateurs des vecteurs « nav » (src/sim/nav.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

## Partie minimale {room (avec son champ), tick, player} dont le champ vient d'être calculé.
static func _field(room: Dictionary, px: float, py: float) -> Dictionary:
	var r: Dictionary = room.duplicate(true)
	r.nav = D6Nav.build_nav(r)
	var game := {"room": r, "tick": 0.0, "player": {"x": px, "y": py}}
	D6Nav.update_nav(game)
	return game

static func _build_nav(a: Array) -> Dictionary:
	var nav: Dictionary = D6Nav.build_nav(a[0])
	return {"cols": nav.cols, "rows": nav.rows, "blocked": Array(nav.blocked), "dist": Array(nav.dist), "lastTick": nav.lastTick}

static func _update_nav(a: Array) -> Dictionary:
	var game := _field(a[0], a[1], a[2])
	var first := Array(game.room.nav.dist)
	game.tick = 14.0
	game.player.x = a[3]
	game.player.y = a[4]
	D6Nav.update_nav(game)
	var early := Array(game.room.nav.dist)
	game.tick = 15.0
	D6Nav.update_nav(game)
	return {"first": first, "early": early, "late": Array(game.room.nav.dist), "lastTick": game.room.nav.lastTick}

static func _nav_direction(a: Array) -> Dictionary:
	var out := {"x": 0.0, "y": 0.0}
	var ret: bool = D6Nav.nav_direction(_field(a[0], a[1], a[2]), a[3], a[4], out)
	return {"ret": ret, "x": out.x, "y": out.y}

static func adapters() -> Dictionary:
	return {"buildNav": _build_nav, "updateNav": _update_nav, "navDirection": _nav_direction}
