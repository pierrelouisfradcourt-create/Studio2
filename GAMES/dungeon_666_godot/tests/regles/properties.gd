extends RefCounted
## Portage de GAMES/dungeon_666/tests/properties.test.mjs.
## Tests de propriétés de la simulation — indépendants des valeurs de tuning : ils vérifient
## des lois (déterminisme, invariants physiques, invulnérabilité, pause des menus,
## jouabilité) et non des nombres.
##
## Les entrées « aléatoires » viennent d'un générateur seedé LOCAL au test (jamais du RNG de
## la partie, jamais de randf) : un échec se rejoue à l'identique. Le `makeRng` du fichier web
## est le mulberry32 de src/core/rng.mjs : ici D6Rng, sur un état propre au test.
## Les angles des entrées passent par cos / sin natifs (Math.cos / Math.sin côté web) : leur
## dernier bit peut différer de V8, ce qui ne change rien aux LOIS vérifiées.

const Bots = preload("res://outils/bots/bots.gd")
const Episode = preload("res://outils/bots/episode.gd")

const SEEDS := [1.0, 2.0, 3.0, 4.0, 5.0]
const DETERMINISM_STEPS := 3000
const INVARIANT_STEPS := 6000
const WALL_EPS := 1e-6 # u : arrondi flottant toléré sur la position contre un mur
const OBSTACLE_TOLERANCE := 1.0 # u : un centre d'ennemi ne doit pas être plus profond que ça
const MAX_EVENTS_PER_STEP := 500 # une image ne doit jamais produire d'avalanche d'événements
const MAX_CHOICE_ROUNDS := 8
const CHOICE_PAUSE_STEPS := 120
const CHOICE_SEARCH_STEPS := 20000
const PLAYABILITY_SEEDS := [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
const SECTION_FLOORS := 18.0 # gate Pierre 2026-10-01 (spec V2) : section de 18 étages
const SECTION_MINUTES := 30.0
const PROBE_DAMAGE := 30.0 # dégâts du projectile témoin (test d'i-frames)
const IFRAME_PROBE_STEPS := 240
const REACH_SAMPLES := 32
const LAYOUT_SEED_LIMIT := 300
const LAYOUT_FLOOR := 2.0 # premier étage où la disposition est tirée au hasard
const DETERMINISM_RNG_SEED := 0xd666
const BOT_SEED := 11.0
const IFRAME_SEED := 7.0
const CHOICE_SEED := 3.0
const CHOICE_RNG_SEED := 99
const RANDOM_SEED_FACTOR := 7919

static func tests(h) -> void:
	h.test("(a) déterminisme : même graine + mêmes entrées => même état ; graines différentes => états différents", func(): _determinisme(h))
	h.test("(a bis) déterminisme du bot skilled : même graine => même partie", func():
		h.egal(_run_skilled(h), _run_skilled(h)))
	h.test("(b) invariants sur 5 graines × 6000 pas — bot skilled", func(): _invariants_skilled(h))
	h.test("(b) invariants sur 5 graines × 6000 pas — entrées aléatoires", func(): _invariants_aleatoires(h))
	h.test("(c) pendant les i-frames (dash puis coup reçu), aucun coup ne retire de PV", func(): _iframes(h))
	h.test("(d) en mode 'choice', stepGame ne fait pas avancer le temps", func(): _pause_menu(h))
	h.test("(e) oracle de jouabilité : le bot skilled bat la section 1 (étage 19) sur au moins une graine", func(): _jouabilite(h))
	h.test("(f) l'objet de récompense d'une salle nettoyée est atteignable, pour chaque disposition", func(): _recompense_atteignable(h))

# ---------------------------------------------------------------- outillage

## InputFrame pseudo-aléatoire : déplacement analogique, visée, et tous les boutons.
static func _random_input(rng: Dictionary) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	var a := D6Rng.rand(rng) * PI * 2.0
	var m := 0.0 if D6Rng.rand(rng) < 0.15 else D6Rng.rand(rng)
	input.moveX = cos(a) * m
	input.moveY = sin(a) * m
	if D6Rng.rand(rng) < 0.3:
		input.aimX = D6Rng.rand(rng) * 2.0 - 1.0
		input.aimY = D6Rng.rand(rng) * 2.0 - 1.0
	input.attack = D6Rng.rand(rng) < 0.5
	input.attackPressed = D6Rng.rand(rng) < 0.1
	input.dashPressed = D6Rng.rand(rng) < 0.04
	input.skillPressed = D6Rng.rand(rng) < 0.02
	input.skillAimX = D6Rng.rand(rng) * 2.0 - 1.0
	input.skillAimY = D6Rng.rand(rng) * 2.0 - 1.0
	input.gadgetPressed = D6Rng.rand(rng) < 0.005
	input.superPressed = D6Rng.rand(rng) < 0.01
	return input

static func _settle_choice(h, game: Dictionary) -> void:
	var i := 0
	while i < MAX_CHOICE_ROUNDS and game.mode == "choice":
		Bots.resolve_choice(game, "skilled")
		i += 1
	h.different(game.mode, "choice", "le menu ouvert doit pouvoir être résolu")

## Fait avancer la partie `steps` pas. `next_input(game)` fournit l'InputFrame ; les menus sont
## résolus, la mort mène à une reprise (respawn) ; `check(game, events)` est appelé après
## chaque pas, avant que les événements ne soient vidés.
static func _drive(h, game: Dictionary, steps: int, next_input: Callable, check = null) -> void:
	for i in steps:
		if game.mode == "choice":
			_settle_choice(h, game)
		if game.mode == "dead":
			D6Game.apply_command(game, {"type": "respawn"})
		if game.mode != "play":
			break
		D6Game.step_game(game, next_input.call(game))
		if check is Callable:
			check.call(game, game.events)
		game.events.clear()

## Empreinte COMPLÈTE : stateHash + états des RNG + build + salle. stateHash seul ne suffit
## pas à distinguer deux graines : il ignore les RNG, et un héros qui marche au hasard contre
## les mêmes murs, salle vidée, converge vers la même position (constaté : graines 1 et 4).
static func _full_fingerprint(game: Dictionary) -> String:
	var r: Dictionary = game.rng
	var run: Dictionary = game.run
	var boons: Array = run.boons.map(func(b): return "%s:%s:%s" % [b.id, b.rarity, D6Js.num_str(b.level)])
	var items: Array = run.items.values().map(func(it): return "-" if it == null or it.get("id") == null else str(it.id))
	return "|".join(PackedStringArray([
		str(D6Game.state_hash(game)), str(int(r.gen.s)), str(int(r.combat.s)), str(int(r.ai.s)),
		"%.6f" % game.time, str(game.room.layout), ",".join(PackedStringArray(boons)), ",".join(PackedStringArray(items)),
	]))

static func _run_random(h, seed_n: float, inputs: Array) -> Dictionary:
	var game: Dictionary = D6Game.create_game({"seed": seed_n})
	var i := [0]
	_drive(h, game, inputs.size(), func(_g):
		i[0] += 1
		return inputs[i[0] - 1])
	return {"hash": D6Game.state_hash(game), "full": _full_fingerprint(game)}

static func _finite(values: Array) -> bool:
	return values.all(func(v): return (v is float or v is int) and is_finite(v))

# ---------------------------------------------------------------- invariants

static func _check_player(h, game: Dictionary, where: String) -> void:
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	h.ok(_finite([p.x, p.y, p.vx, p.vy]), "%s : position/vitesse du héros non finie" % where)
	var lo: float = room.pad + p.r - WALL_EPS
	h.ok(p.x >= lo and p.x <= room.w - lo and p.y >= lo and p.y <= room.h - lo, "%s : héros hors des murs (%s, %s)" % [where, str(p.x), str(p.y)])
	h.ok(p.hp >= 0.0 and p.hp <= p.maxHp, "%s : PV hors bornes (%s / %s)" % [where, str(p.hp), str(p.maxHp)])
	var max_dash: float = D6Player.max_dash_charges(game)
	h.ok(p.dashCharges >= 0.0 and p.dashCharges <= max_dash, "%s : charges de dash hors bornes (%s / %s)" % [where, str(p.dashCharges), str(max_dash)])
	h.ok(p.superCharge >= 0.0 and p.superCharge <= 1.0, "%s : jauge de Super hors [0, 1] (%s)" % [where, str(p.superCharge)])

static func _inside_obstacle(room: Dictionary, x: float, y: float, tol: float):
	for o in room.obstacles:
		if x > o.x0 + tol and x < o.x1 - tol and y > o.y0 + tol and y < o.y1 - tol:
			return o
	return null

static func _check_enemies(h, game: Dictionary, where: String) -> void:
	for e in game.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var qui := "%s : %s#%s" % [where, e.kind, D6Js.num_str(e.id)]
		h.ok(_finite([e.x, e.y, e.vx, e.vy, e.kvx, e.kvy]), "%s position/vitesse non finie" % qui)
		var o = _inside_obstacle(game.room, e.x, e.y, OBSTACLE_TOLERANCE)
		h.ok(o == null, "%s vivant DANS un obstacle (%.1f, %.1f) %s" % [qui, e.x, e.y, JSON.stringify(o)])

static func _a_ennemi_vivant(game: Dictionary) -> bool:
	return game.enemies.any(func(e): return not D6Js.truthy(e.get("dead")))

## Vérificateur d'invariants ; `cover` compte ce que le test a réellement exercé.
static func _invariant_checker(h, label: String, cover: Dictionary) -> Callable:
	return func(game: Dictionary, events: Array):
		var where := "%s tick %s étage %s" % [label, D6Js.num_str(game.tick), D6Js.num_str(game.run.floor)]
		_check_player(h, game, where)
		_check_enemies(h, game, where)
		h.ok(events.size() <= MAX_EVENTS_PER_STEP, "%s : %d événements en une image" % [where, events.size()])
		cover.enemySteps += 1 if _a_ennemi_vivant(game) else 0
		cover.maxFloor = maxf(cover.maxFloor, game.run.floor)

# ---------------------------------------------------------------- (a) déterminisme

static func _determinisme(h) -> void:
	var rng: Dictionary = D6Rng.create_rng(DETERMINISM_RNG_SEED)
	var inputs: Array = []
	for i in DETERMINISM_STEPS:
		inputs.append(_random_input(rng))
	var states := {}
	for seed_n in SEEDS:
		var a := _run_random(h, seed_n, inputs)
		var b := _run_random(h, seed_n, inputs)
		h.egal(a.hash, b.hash, "graine %s : même graine, mêmes entrées, stateHash différent" % D6Js.num_str(seed_n))
		h.egal(a.full, b.full, "graine %s : même graine, mêmes entrées, état complet différent" % D6Js.num_str(seed_n))
		states[a.full] = true
	h.egal(states.size(), SEEDS.size(), "des graines différentes donnent le même état :\n  %s" % "\n  ".join(PackedStringArray(states.keys())))

static func _run_skilled(h) -> int:
	var game: Dictionary = D6Game.create_game({"seed": BOT_SEED})
	var mem := {}
	_drive(h, game, DETERMINISM_STEPS, func(g): return Bots.play("skilled", g, mem))
	return D6Game.state_hash(game)

# ---------------------------------------------------------------- (b) invariants

static func _invariants_skilled(h) -> void:
	var cover := {"enemySteps": 0, "maxFloor": 0.0}
	for seed_n in SEEDS:
		var game: Dictionary = D6Game.create_game({"seed": seed_n})
		var mem := {}
		_drive(h, game, INVARIANT_STEPS, func(g): return Bots.play("skilled", g, mem), _invariant_checker(h, "skilled graine %s" % D6Js.num_str(seed_n), cover))
	h.ok(cover.enemySteps > 0, "couverture : des ennemis doivent avoir été présents")
	h.ok(cover.maxFloor > 1.0, "couverture : le bot doit avoir changé de salle")

static func _invariants_aleatoires(h) -> void:
	var cover := {"enemySteps": 0, "maxFloor": 0.0}
	for seed_n in SEEDS:
		var game: Dictionary = D6Game.create_game({"seed": seed_n})
		var rng: Dictionary = D6Rng.create_rng(int(seed_n) * RANDOM_SEED_FACTOR)
		_drive(h, game, INVARIANT_STEPS, func(_g): return _random_input(rng), _invariant_checker(h, "aléatoire graine %s" % D6Js.num_str(seed_n), cover))
	h.ok(cover.enemySteps > 0, "couverture : des ennemis doivent avoir été présents")

# ---------------------------------------------------------------- (c) i-frames

## Salle vidée de ses ennemis et de ses vagues : seuls nos projectiles témoins frappent.
static func _quiet_game(seed_n: float) -> Dictionary:
	var game: Dictionary = D6Game.create_game({"seed": seed_n})
	game.enemies.clear()
	game.spawns.clear()
	game.room.waves = []
	return game

## Pose un projectile ennemi immobile sur le héros (le coup part via la sim).
static func _probe_hit(game: Dictionary) -> void:
	var p: Dictionary = game.player
	D6Projectiles.spawn_projectile(game, {"owner": "enemy", "kind": "probe", "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "r": 4.0, "damage": PROBE_DAMAGE, "range": 1e9})

static func _iframes(h) -> void:
	var game := _quiet_game(IFRAME_SEED)
	var p: Dictionary = game.player
	var dash: Dictionary = D6Game.empty_input()
	dash.dashPressed = true
	dash.moveX = 1.0
	D6Game.step_game(game, dash)
	h.egal(p.state, "dash", "le dash doit partir")
	var protected_hits := 0
	var landed := 0
	for i in IFRAME_PROBE_STEPS:
		var hp_before: float = p.hp
		# i-frames encore actives APRÈS le décompte de cette image (sinon le coup est légitime).
		var shielded: bool = p.iframes > 1.0 / 60.0 + 1e-9 and game.hitstop <= 0.0
		_probe_hit(game)
		D6Game.step_game(game, D6Game.empty_input())
		game.projectiles.clear()
		if shielded:
			h.egal(p.hp, hp_before, "tick %s : PV retirés pendant les i-frames (%.3f s restantes)" % [D6Js.num_str(game.tick), p.iframes])
			protected_hits += 1
		elif p.hp < hp_before:
			landed += 1
			# Un coup qui porte ouvre des i-frames : la propriété doit tenir aussi pour elles.
			h.ok(p.iframes > 0.0, "un coup reçu doit accorder des i-frames")
		game.events.clear()
		if p.state == "dead":
			break
	h.ok(protected_hits > 0, "le test doit avoir provoqué des coups pendant des i-frames")
	h.ok(landed > 0, "témoin : hors i-frames, le projectile doit porter")

# ---------------------------------------------------------------- (d) pause des menus

static func _pause_menu(h) -> void:
	var game: Dictionary = D6Game.create_game({"seed": CHOICE_SEED})
	var mem := {}
	var i := 0
	while i < CHOICE_SEARCH_STEPS and game.mode == "play":
		D6Game.step_game(game, Bots.play("skilled", game, mem))
		game.events.clear()
		i += 1
	h.egal(game.mode, "choice", "le bot doit atteindre un menu (récompense de salle)")
	var tick: float = game.tick
	var time: float = game.time
	var hash := D6Game.state_hash(game)
	var rng: Dictionary = D6Rng.create_rng(CHOICE_RNG_SEED)
	for k in CHOICE_PAUSE_STEPS:
		D6Game.step_game(game, _random_input(rng))
	h.egal(game.tick, tick, "game.tick a avancé pendant un menu")
	h.egal(game.time, time, "game.time a avancé pendant un menu")
	h.egal(D6Game.state_hash(game), hash, "l'état a changé pendant un menu")

# ---------------------------------------------------------------- (e) jouabilité

static func _jouabilite(h) -> void:
	var outcomes: Array = []
	for seed_n in PLAYABILITY_SEEDS:
		var r: Dictionary = Episode.run_episode("skilled", seed_n, {"floors": SECTION_FLOORS, "minutes": SECTION_MINUTES})
		outcomes.append("graine %s : %s, étage %s" % [D6Js.num_str(seed_n), r.outcome, D6Js.num_str(r.floorReached)])
		if r.floorReached >= SECTION_FLOORS + 1.0:
			h.ok(true, "section 1 battue")
			return
	h.ok(false, "aucune graine ne bat la section 1 :\n  %s" % "\n  ".join(PackedStringArray(outcomes)))

# ---------------------------------------------------------------- (f) accessibilité de la récompense

## Vide la salle et la termine via la sim : l'objet de récompense apparaît.
static func _clear_room(game: Dictionary) -> void:
	game.enemies.clear()
	game.spawns.clear()
	game.room.waveIndex = float(game.room.waves.size() - 1)
	D6Game.step_game(game, D6Game.empty_input())
	game.events.clear()

## Le héros peut-il se placer assez près de l'objet pour le toucher sans être dans un obstacle ?
static func _interact_reachable(game: Dictionary) -> bool:
	var it: Dictionary = game.room.interact
	var p: Dictionary = game.player
	var reach: float = p.r + it.r
	for f in [0.0, 0.5, 0.95]:
		for k in REACH_SAMPLES:
			var a := (float(k) / float(REACH_SAMPLES)) * PI * 2.0
			var x: float = it.x + cos(a) * reach * f
			var y: float = it.y + sin(a) * reach * f
			if not D6Physics.point_blocked(game.room, x, y, p.r):
				return true
	return false

static func _recompense_atteignable(h) -> void:
	var seen := {}
	for seed_i in range(1, LAYOUT_SEED_LIMIT + 1):
		var game: Dictionary = D6Game.create_game({"seed": float(seed_i), "startFloor": LAYOUT_FLOOR})
		var layout = game.room.layout
		if seen.has(layout):
			continue
		_clear_room(game)
		if not h.ok(game.room.interact != null, "graine %d : la salle nettoyée doit poser sa récompense" % seed_i):
			continue
		seen[layout] = {"seed": seed_i, "reachable": _interact_reachable(game), "at": [game.room.interact.x, game.room.interact.y]}
	var blocked: Array = []
	for layout in seen:
		var v: Dictionary = seen[layout]
		if not v.reachable:
			blocked.append("%s (graine %d, objet en %s, %s)" % [layout, v.seed, D6Js.num_str(D6Js.jround(v.at[0])), D6Js.num_str(D6Js.jround(v.at[1]))])
	h.egal(blocked, [], "récompense inaccessible => portes jamais ouvertes (blocage) : %s" % " ; ".join(PackedStringArray(blocked)))
