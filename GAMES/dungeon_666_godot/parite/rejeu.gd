extends RefCounted
## Rejeu de parité : rejoue une partie notée par la simulation web (tools/traces.mjs) et compare
## l'état de la partie Godot à chaque point de contrôle.
##
## Une trace : {name, options, steps, ticks}. Un pas :
##   [0, mx, my, ax, ay, drapeaux, sx, sy]  une image d'entrées (analogiques en 1/1024)
##   [1, commande, acceptée]                une commande de menu tentée (Godot doit répondre pareil)
##   [2, empreinte]                         un point de contrôle
## Égalité stricte sur le discret, 1e-6 sur les nombres (D6Comparer).

const Q := 1024.0
const FLAGS := ["attack", "attackPressed", "dashPressed", "skillPressed", "gadgetPressed", "superPressed"]
const TRACES_DIR := "res://parite/traces/"

## Empreinte d'état : la même que tools/traces.mjs (digest), clé pour clé.
static func digest(game: Dictionary, events: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	var doors: Array = []
	for d in room.doors:
		doors.append("%s%s" % [d.reward, "+" if D6Js.truthy(d.get("open")) else "-"])
	var choice = game.get("choice")
	return {
		"tick": game.tick, "time": game.time, "mode": game.mode, "floor": game.run.floor,
		"gold": game.run.gold, "souls": game.meta.souls,
		"rng": [game.rng.gen.s, game.rng.combat.s, game.rng.ai.s],
		"nextId": game.nextId, "hitstop": game.hitstop, "bank": game.hitstopBank,
		"p": [p.x, p.y, p.vx, p.vy, p.hp, p.maxHp, p.state, p.facing, p.dashCharges, p.superCharge, p.gadgetCharges, p.skillCd, p.iframes, p.freeze],
		"e": game.enemies.map(func(e): return [e.id, e.kind, e.state, e.x, e.y, e.hp, e.stun, 1 if D6Js.truthy(e.get("dead")) else 0, D6Js.nz(e.get("eliteMod"), "")]),
		"pr": game.projectiles.map(func(o): return [o.x, o.y]),
		"hz": game.hazards.size(), "pk": game.pickups.size(), "sp": game.spawns.size(),
		"boons": game.run.boons.map(func(b): return "%s:%s:%s" % [b.id, D6Js.num_str(b.level), b.rarity]),
		"room": [room.kind, D6Js.nz(room.get("layout"), ""), room.waveIndex, 1 if D6Js.truthy(room.get("cleared")) else 0, ",".join(doors)],
		"choice": choice.kind if choice is Dictionary else "",
		"ev": events,
		"tel": [game.telemetry.kills, game.telemetry.damageTaken, game.telemetry.damageDealt, game.telemetry.dodges],
	}

static func _input(step: Array) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	input.moveX = step[1] / Q
	input.moveY = step[2] / Q
	input.aimX = step[3] / Q
	input.aimY = step[4] / Q
	var flags := int(step[5])
	for i in FLAGS.size():
		input[FLAGS[i]] = (flags & (1 << i)) != 0
	input.skillAimX = step[6] / Q
	input.skillAimY = step[7] / Q
	return input

static func _options(o: Dictionary) -> Dictionary:
	var out := {"seed": o.seed, "startFloor": o.startFloor, "sandbox": o.sandbox, "practice": o.practice, "godMode": o.godMode}
	if o.get("meta") != null:
		out.meta = o.meta
	if o.get("tuning") != null:
		out.tuning = o.tuning
	return out

static func _drain(game: Dictionary, events: Dictionary) -> void:
	for ev in game.events:
		events[ev.type] = events.get(ev.type, 0) + 1
	game.events.clear()

## Rejoue une trace. Rend {name, ok, checks, steps, message} ; `message` décrit le 1er écart.
static func replay(trace: Dictionary) -> Dictionary:
	var res := {"name": trace.name, "ok": true, "checks": 0, "steps": 0, "message": ""}
	var game = D6Game.create_game(_options(trace.options))
	if not (game is Dictionary):
		res.ok = false
		res.message = "create_game n'a pas rendu de partie"
		return res
	var events := {}
	for step in trace.steps:
		res.steps += 1
		match int(step[0]):
			0:
				D6Game.step_game(game, _input(step))
				_drain(game, events)
			1:
				var ok := D6Js.truthy(D6Game.apply_command(game, step[1]))
				if ok != (step[2] != 0.0):
					res.ok = false
					res.message = "pas %d (image %s) : commande %s %s, la référence l'a %s" % [res.steps, D6Js.num_str(game.tick), str(step[1]), "acceptée" if ok else "refusée", "acceptée" if step[2] != 0.0 else "refusée"]
					return res
			2:
				_drain(game, events)
				res.checks += 1
				var d := D6Comparer.diff(digest(game, events), step[1], D6Comparer.TOL, "")
				events = {}
				if d != "":
					res.ok = false
					res.message = "point de contrôle %d (image %s, pas %d) — %s" % [res.checks, D6Js.num_str(step[1].tick), res.steps, d]
					return res
	return res

static func load_trace(name: String):
	return D6Js.read_exact(TRACES_DIR + name + ".json")

static func names() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(TRACES_DIR):
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out
