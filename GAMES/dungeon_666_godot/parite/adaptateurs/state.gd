extends RefCounted
## Adaptateurs des vecteurs « state » (src/sim/state.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.
##
## Ce fichier tient aussi les deux outils que partagent les adaptateurs du lot « socle de partie »
## (ils le préchargent) : `tuning` et `make_game`, pendants de createTuning et de gameMaker dans
## tools/vecteurs/socle_partie.mjs.

static var _base_tuning = null

## Tuning de la partie pour une surcharge donnée. Sans surcharge, le MÊME dictionnaire est rendu à
## chaque appel : à réserver aux fonctions qui ne modifient pas le tuning (sinon `fresh`).
static func tuning(over, fresh: bool = false) -> Dictionary:
	if over != null or fresh:
		return D6Data.create_tuning(over)
	if _base_tuning == null:
		_base_tuning = D6Data.create_tuning()
	return _base_tuning

## Partie minimale reconstruite depuis une fiche {seed, tuning, nextId, tick, meta, run, player}.
static func make_game(s: Dictionary) -> Dictionary:
	return {
		"tuning": D6Data.create_tuning(s.tuning),
		"rng": {"gen": D6Rng.create_rng(s.seed)},
		"nextId": s.nextId,
		"tick": s.tick,
		"events": [],
		"meta": D6Js.clone(s.meta),
		"run": D6Js.clone(s.run),
		"player": D6Js.clone(s.player),
	}

static func _new_id(a: Array) -> Dictionary:
	var g := {"nextId": a[0]}
	var ids: Array = []
	for i in int(a[1]):
		ids.append(D6State.new_id(g))
	return {"ids": ids, "next": g.nextId}

static func _emit(a: Array) -> Dictionary:
	var g := {"tick": a[0], "events": [{"type": "avant", "tick": 0.0}]}
	var ev := D6State.emit(g, a[1], D6Js.clone(a[2]))
	return {"ev": ev, "count": g.events.size(), "last": g.events[g.events.size() - 1]}

static func adapters() -> Dictionary:
	return {
		"newId": _new_id,
		"emit": _emit,
		"baseStats": func(_a): return D6State.base_stats(),
		"createPlayer": func(a): return D6State.create_player(tuning(a[0]), a[1], a[2]),
		"createTelemetry": func(_a): return D6State.create_telemetry(),
	}
