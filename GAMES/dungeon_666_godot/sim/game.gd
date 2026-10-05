class_name D6Game
extends RefCounted
## Portage de src/sim/game.mjs.
## Point d'entrée de la simulation. Déterministe : même graine + mêmes InputFrames
## => même partie, à l'octet près. Aucune dépendance au DOM, à l'horloge ou à randf.
##
##   var game = D6Game.create_game({"seed": seed})
##   D6Game.step_game(game, input_frame)   # un pas fixe de 1/60 s
##   D6Game.apply_command(game, {"type": "choose", "index": 0})   # menus (bénédiction, butin…)
##   game.events                            # événements de l'image, à vider par l'appelant

const Arbre = preload("res://sim/tree.gd")
const Neuves = preload("res://sim/kit_neuves.gd")
const DT := 1.0 / 60.0
const HASH_BASIS := 2166136261
const HASH_PRIME := 16777619

static func empty_input() -> Dictionary:
	return {
		"moveX": 0.0, "moveY": 0.0, "aimX": 0.0, "aimY": 0.0,
		"attack": false, "attackPressed": false, "dashPressed": false,
		"skill1Pressed": false, "skill1AimX": 0.0, "skill1AimY": 0.0,
		"skill2Pressed": false, "skill2AimX": 0.0, "skill2AimY": 0.0,
		"skill3Pressed": false, "skill3AimX": 0.0, "skill3AimY": 0.0,
	}

## options : { seed, tuning (surcharges partielles), startFloor, meta, godMode, items, sandbox, practice }
## (une clé absente ou nulle = défaut).
## meta    : le PROFIL PERMANENT (profile) — classe et kit choisis, équipement, coffre,
##           déblocages, Âmes, bourse, checkpoints. Une forme ancienne ({checkpoints, bestFloor})
##           est complétée. La partie en garde une COPIE (game.meta) que main sauvegarde.
## Tout ce qui vit dans game.run est TEMPORAIRE : la mort le remet à zéro (run, respawn).
static func create_game(options = null) -> Dictionary:
	var opts: Dictionary = options if options is Dictionary else {}
	var seed_n: float = float(D6Js.u32(D6Js.nz(opts.get("seed"), 1.0)))
	var tuning: Dictionary = D6Data.create_tuning(opts.get("tuning"))
	D6Lab.apply_lab(tuning)
	var meta: Dictionary
	if D6Js.truthy(opts.get("meta")):
		meta = D6Profile.sanitize_profile(D6Js.clone(opts.meta), tuning)
	else:
		meta = D6Profile.new_profile(tuning)
	var start_floor = D6Js.nz(opts.get("startFloor"), 1.0)
	var game := _new_game(seed_n, tuning, meta, opts, start_floor)
	# Équipement PERMANENT : celui du profil (complété par l'équipement de départ à la toute
	# première partie), puis d'éventuelles surcharges explicites. run.items EST l'équipement du
	# profil (même objet) : ce qu'on équipe en donjon est conservé.
	var starters: Dictionary = D6Loot.starter_items(game)
	for slot in starters.keys():
		if not D6Js.truthy(meta.equipment.get(slot)) and D6Js.truthy(starters[slot]):
			meta.equipment[slot] = starters[slot]
	var items = opts.get("items")
	if items is Dictionary:
		meta.equipment.merge(items, true)
	# Tout objet qui entre dans le profil y reçoit son identifiant (comme au coffre) : le profil en
	# mémoire est celui qu'on relira du disque.
	for slot in meta.equipment:
		if meta.equipment[slot] is Dictionary:
			D6Profile.ensure_uid(meta, meta.equipment[slot])
	game.run.items = meta.equipment
	game.run.gold = meta.gold # la bourse suit le héros d'un run à l'autre
	if not game.sandbox and not game.practice:
		meta.stats.runs += 1.0
	Arbre.apply(game) # arbre de compétences : rangs et améliorations exclusives de la classe jouée
	D6Loadout.resolve_kit(game)
	game.player = D6State.create_player(tuning, 0.0, 0.0)
	D6Loadout.reset_slots(game)
	D6Stats.recompute_stats(game)
	game.player.hp = game.player.maxHp
	D6Run.enter_floor(game, start_floor, {"reward": "boon", "family": "colere"})
	return game

## L'état d'une partie neuve, avant l'équipement, le kit, le héros et la première salle.
static func _new_game(seed_n: float, tuning: Dictionary, meta: Dictionary, opts: Dictionary, start_floor) -> Dictionary:
	return {
		"seed": seed_n,
		"tuning": tuning,
		"tick": 0.0,
		"time": 0.0,
		"rng": {
			"gen": D6Rng.create_rng(D6Rng.hash_seed(seed_n, [1])),
			"combat": D6Rng.create_rng(D6Rng.hash_seed(seed_n, [2])),
			"ai": D6Rng.create_rng(D6Rng.hash_seed(seed_n, [3])),
		},
		"mode": "play", # play | choice | dead | victory | town (run terminé : retour en Ville)
		"choice": null,
		"hitstop": 0.0,
		"hitstopBank": tuning.hitstopBank.max,
		"deathT": 0.0,
		"godMode": D6Js.truthy(opts.get("godMode")),
		"sandbox": D6Js.truthy(opts.get("sandbox")), # arène d'essai : vagues sans fin, ni portes ni récompenses
		"practice": D6Js.truthy(opts.get("practice")), # entraînement contre un Gardien : ni Âmes, ni checkpoint, ni taxe
		"nextId": 1.0,
		"events": [],
		"telemetry": D6State.create_telemetry(),
		"meta": meta,
		"run": D6Run.create_run(start_floor),
		"kit": null, # kit résolu (loadout) : classe, arme, trois emplacements d'action, Super
		"player": null,
		"room": null,
		"info": null,
		"enemies": [],
		"projectiles": [],
		"hazards": [],
		"pickups": [],
		"spawns": [],
		"allies": [], # limiers de la Meute des Limbes (D6KitSupers) : jamais dans `enemies`
	}

static func step_game(game: Dictionary, input = null) -> void:
	if game.mode != "play":
		return
	var dt := DT
	game.tick += 1.0
	var dash_wanted: bool = D6Js.truthy(D6Player.read_input(game, input if input != null else empty_input()))
	# Gel LOCAL (D8) : le dash l'interrompt aussi, sans attendre.
	if game.player.freeze > 0.0 and dash_wanted and D6Js.truthy(game.tuning.dash.get("cancelsHitstop")) and D6Js.truthy(D6Player.can_dash(game)):
		game.player.freeze = 0.0
	if game.hitstop > 0.0:
		# Le dash interrompt le gel d'impact : la réactivité passe avant l'emphase.
		if dash_wanted and D6Js.truthy(game.tuning.dash.get("cancelsHitstop")) and D6Js.truthy(D6Player.can_dash(game)):
			game.hitstop = 0.0
		else:
			game.hitstop = maxf(0.0, game.hitstop - dt)
			return
	game.time += dt
	var hb: Dictionary = game.tuning.hitstopBank
	game.hitstopBank = minf(hb.max, game.hitstopBank + hb.refill * dt)
	D6Player.update_player(game, dt)
	Neuves.tick(game, dt) # compétences neuves : braises semées, garde, parade, marques
	D6KitSupers.tick(game, dt) # ultimes qui durent : forme, limiers ; et les leurres
	D6Nav.update_nav(game)
	D6Enemies.update_enemies(game, dt)
	D6Projectiles.update_projectiles(game, dt)
	D6Projectiles.update_hazards(game, dt)
	D6Room.update_spawns(game, dt)
	_update_pickups(game, dt)
	D6Projectiles.compact(game.enemies)
	_update_flow(game, dt)

static func _update_pickups(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning.room
	# Un butin tombé glisse (room.pickupFriction) ; il n'est aimanté ni ramassé avant room.pickupSettle s.
	var friction := D6Trig.exp(-t.pickupFriction * dt)
	var pickups: Array = game.pickups
	var i := 0
	while i < pickups.size():
		var pk = pickups[i]
		i += 1
		pk.age += dt
		var d2 := D6Geo.dist2(pk.x, pk.y, p.x, p.y)
		var settle: bool = pk.age > t.pickupSettle
		if settle and p.state != "dead" and d2 < t.pickupMagnetRange * t.pickupMagnetRange:
			var d := sqrt(d2)
			if d == 0.0 or is_nan(d):
				d = 1.0
			pk.vx = ((p.x - pk.x) / d) * t.pickupMagnetSpeed
			pk.vy = ((p.y - pk.y) / d) * t.pickupMagnetSpeed
		else:
			pk.vx *= friction
			pk.vy *= friction
		D6Physics.move_circle(game.room, pk, pk.vx * dt, pk.vy * dt)
		var reach: float = p.r + pk.r
		if settle and p.state != "dead" and d2 < reach * reach:
			pk.dead = true
			if pk.kind == "gold":
				game.run.gold += pk.value
				D6State.emit(game, "pickup", {"kind": "gold", "x": pk.x, "y": pk.y, "amount": pk.value})
			elif pk.kind == "heal":
				D6Combat.heal_player(game, pk.value, true)
				D6State.emit(game, "pickup", {"kind": "heal", "x": pk.x, "y": pk.y, "amount": pk.value})
	D6Projectiles.compact(game.pickups)

static func _update_flow(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	if p.state == "dead":
		game.deathT += dt
		if game.deathT >= game.tuning.player.deathDelay: # s de ralenti/agonie avant l'écran de mort
			game.mode = "dead"
			D6Run.on_death(game)
			D6State.emit(game, "gameOver", {"floor": game.run.floor})
		return
	if D6Room.update_waves(game):
		if game.sandbox:
			D6Room.refill_sandbox_waves(game)
		else:
			D6Run.on_room_clear(game)
	if game.mode != "play":
		return
	var it = room.get("interact")
	if it != null and not D6Js.truthy(it.get("used")):
		var reach: float = p.r + it.r
		if D6Geo.dist2(p.x, p.y, it.x, it.y) < reach * reach:
			D6Run.open_interact(game)
	if game.mode != "play":
		return
	var door := D6Room.door_touched(game)
	if door >= 0:
		var chosen: Dictionary = room.doors[door]
		# Portail du checkpoint : retour en Ville (fin du run, le temporaire est abandonné).
		if chosen.reward == "town":
			D6Run.return_to_town(game)
		else:
			D6Run.enter_floor(game, game.run.floor + 1.0, chosen)

static func apply_command(game: Dictionary, cmd: Dictionary) -> bool:
	return D6Run.apply_command(game, cmd)

## Un pas de l'empreinte : Math.round(v * 1000) | 0 (entier 32 bits signé), puis
## Math.imul(h ^ x, 16777619) >>> 0. Seuls les 32 bits bas de x comptent.
static func _mix(h: int, v) -> int:
	var scaled := D6Js.jround(float(v) * 1000.0)
	var x := 0
	if not is_nan(scaled) and not is_inf(scaled):
		x = int(fmod(scaled, D6Js.U32)) & D6Js.MASK
	return D6Js.imul(h ^ x, HASH_PRIME) & D6Js.MASK

## Empreinte compacte de l'état (tests de déterminisme).
static func state_hash(game: Dictionary) -> int:
	var p: Dictionary = game.player
	var h := HASH_BASIS
	h = _mix(h, game.tick)
	h = _mix(h, game.time)
	h = _mix(h, game.rng.gen.s)
	h = _mix(h, game.rng.combat.s)
	h = _mix(h, game.rng.ai.s)
	h = _mix(h, game.run.boons.size())
	h = _mix(h, game.hitstop)
	h = _mix(h, p.x)
	h = _mix(h, p.y)
	h = _mix(h, p.hp)
	h = _mix(h, game.run.floor)
	h = _mix(h, game.run.gold)
	for e in game.enemies:
		h = _mix(h, e.id)
		h = _mix(h, e.x)
		h = _mix(h, e.y)
		h = _mix(h, e.hp)
	for pr in game.projectiles:
		h = _mix(h, pr.x)
		h = _mix(h, pr.y)
	return h & D6Js.MASK
