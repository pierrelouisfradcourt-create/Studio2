class_name D6Spawns
extends RefCounted
## Portage de src/sim/spawns.mjs.
## File d'apparitions télégraphiées : un cercle d'invocation est visible `warn` secondes
## avant que l'ennemi n'apparaisse — jamais d'apparition injuste sous les pieds du héros.
## Module feuille (aucun import de sim) : utilisable par la salle comme par le boss.

const PLACEMENT_TRIES := 40.0
const PLACEMENT_MARGIN := 6.0 # u ajoutées au rayon pour le test d'obstacle
const CROWD_DIST := 50.0 # u : distance minimale à une autre apparition en attente

static func queue_spawn(game: Dictionary, kind, x: float, y: float, opts = null) -> Dictionary:
	if opts == null:
		opts = {}
	var warn = D6Js.nz(opts.get("warn"), game.tuning.room.spawnWarn)
	var s := {
		"id": D6State.new_id(game), "kind": kind, "x": x, "y": y, "t": warn, "warn": warn,
		"elite": opts.get("elite"), "summoned": D6Js.truthy(opts.get("summoned")),
	}
	game.spawns.append(s)
	D6State.emit(game, "spawnWarn", {"id": s.id, "x": x, "y": y, "enemy": kind, "elite": D6Js.truthy(s.elite)})
	return s

## Cherche un point libre, loin du héros et des autres apparitions. null si introuvable.
static func find_spawn_point(game: Dictionary, r: float, min_player_dist: float, near = null):
	var room: Dictionary = game.room
	var p: Dictionary = game.player
	var i := 0.0
	while i < PLACEMENT_TRIES:
		var attempt := i
		i += 1.0
		var x: float
		var y: float
		if near != null:
			var a: float = D6Rng.rand(game.rng.gen) * PI * 2.0
			var d: float = near.minR + D6Rng.rand(game.rng.gen) * (near.maxR - near.minR)
			x = near.x + D6Trig.cos(a) * d
			y = near.y + D6Trig.sin(a) * d
		else:
			x = room.pad + r + D6Rng.rand(game.rng.gen) * (room.w - 2.0 * (room.pad + r))
			y = room.pad + r + D6Rng.rand(game.rng.gen) * (room.h - 2.0 * (room.pad + r))
		if D6Physics.ground_blocked(room, x, y, r + PLACEMENT_MARGIN): # ni mur, ni pilier, ni rivière, ni obstacle bas
			continue
		# La distance minimale au héros se relâche au fil des essais (salle encombrée).
		var relax := 1.0 - attempt / PLACEMENT_TRIES
		var min_d := min_player_dist * relax
		if D6Geo.dist2(x, y, p.x, p.y) < min_d * min_d:
			continue
		var crowded := false
		for s in game.spawns:
			if D6Geo.dist2(x, y, s.x, s.y) < CROWD_DIST * CROWD_DIST:
				crowded = true
		if crowded:
			continue
		return {"x": x, "y": y}
	return null
