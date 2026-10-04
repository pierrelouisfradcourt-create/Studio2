extends RefCounted
## Portage de GAMES/dungeon_666/tests/properties_strict.test.mjs.
## Propriétés STRICTES — complètent tests/regles/properties.gd là où un test de mutation a
## montré qu'un défaut de la sim passait inaperçu :
##   dash sans i-frames, dash immobile, esquive non comptée      -> (g)
##   menu qui consomme les entrées (gadget tiré pendant la pause) -> (h)
##   stateHash constant ou aveugle aux RNG                        -> (i)
##   Math.random / horloge dans la sim ou les bots                -> (j) (non portable)
##   ennemis poussés dans les murs, héros dans un obstacle,
##   soin au-delà des PV max                                      -> (k)
##   salle de boss vide (oracle de jouabilité trivialement vert)  -> (l)
##   récompense posée hors d'atteinte, disposition non couverte   -> (m)
##   bot qui triche (lit le RNG, un compteur caché) ou qui écrit  -> (n) (écriture seulement)
## Comme le fichier d'origine : des lois, pas des valeurs de tuning (les seuils lisent
## game.tuning). `makeRng` du web = mulberry32 de src/core/rng.mjs = D6Rng sur un état local.
## Angles des entrées et Math.hypot : cos / sin / sqrt natifs (dernier bit libre, lois inchangées).

const Bots = preload("res://outils/bots/bots.gd")
const Episode = preload("res://outils/bots/episode.gd")

const DT := 1.0 / 60.0
const GEOM_EPS := 0.5 # u : arrondi toléré sur un contact mur / obstacle
const PROBE_RADIUS := 40.0 # u : projectile témoin assez gros pour toucher même pendant un dash
const PROBE_DAMAGE := 30.0
const DASH_SEED := 7.0
const DASH_MAX_STEPS := 120
const DASH_DISTANCE_TOLERANCE := 0.25 # fraction de dash.distance (sortie de dash à la course)
const MENU_SEED := 3.0
const MENU_SEARCH_STEPS := 20000
const MENU_PAUSE_STEPS := 120
const MENU_RNG_SEED := 0x5eed
const HASH_SEED := 1.0
const HASH_SEARCH_STEPS := 600
const SECTION_SEEDS := [1.0, 2.0, 3.0, 4.0]
# Gate Pierre 2026-10-01 (spec V2) : section de 18 étages, Gardien au 18e.
const SECTION_FLOORS := 18.0
const SECTION_TICK_CAP := 30.0 * 60.0 * 60.0 # 30 min de sim
const RANDOM_START_FLOORS := [2.0, 3.0, 9.0, 17.0, 18.0] # combat, mi-section, antichambre, Gardien
const RANDOM_SEEDS := [1.0, 2.0, 3.0]
const RANDOM_STEPS := 2000
const RANDOM_SEED_FACTOR := 7919
const MIN_OBSTACLE_LAYOUTS := 3 # dispositions à obstacles réellement exercées avec des ennemis
const PLAYABILITY_SEEDS := [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
const PLAYABILITY_MINUTES := 30.0
const LAYOUT_SEED_LIMIT := 300
const LAYOUT_FLOOR := 2.0
const BOSS_FLOOR := 18.0
# Miroir de la liste du fichier web (LAYOUTS de combat et BOSS_LAYOUT dans src/sim/room.mjs).
const EXPECTED_LAYOUTS := ["open", "pillars", "center", "lanes", "bastions", "scatter", "boss"]
const PATH_CELL := 8.0 # u : pas de la grille de recherche de chemin
const PATH_NEIGHBOURS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const AUDIT_STEPS := 2500
const AUDIT_SEED := 4.0
const MAX_CHOICE_ROUNDS := 8

static func tests(h) -> void:
	h.test("(g) le dash accorde des i-frames, un coup pendant le dash est une esquive comptée, et le dash déplace le héros", func(): _dash(h))
	h.test("(h) menu ouvert : pause TOTALE — aucun champ de l'état ne change, aucun événement, même tous boutons pressés", func(): _pause_totale(h))
	h.test("(i) stateHash est sensible : héros, ennemi, RNG, temps, étage, or changent l'empreinte", func(): _empreinte_sensible(h))
	h.test("(j) ni la sim ni les bots n'appellent Math.random, Date.now ou performance.now", func():
		h.non_portable("le test web piège Math.random / Date.now / performance.now en les remplaçant ; GDScript ne permet pas de remplacer randf, randi ni Time (pas de fonctions globales réassignables)"))
	h.test("(k) invariants stricts (cercles entiers, murs, obstacles, PV) — sections complètes du bot skilled", func(): _stricts_sections(h))
	h.test("(k bis) invariants stricts — entrées aléatoires, départ dans chaque type de salle (combat, mi-section, antichambre, Gardien)", func(): _stricts_aleatoires(h))
	h.test("(l) le run qui bat la section 1 a réellement tué le boss (l'oracle ne passe pas sur une salle vide)", func(): _boss_reellement_tue(h))
	h.test("(m) chaque disposition (boss compris) est couverte et sa récompense est atteignable À PIED depuis l'entrée", func(): _dispositions(h))
	h.test("(n) les bots n'écrivent jamais dans la partie et ne lisent ni le RNG ni les compteurs cachés", func(): _bots_honnetes(h))

# ---------------------------------------------------------------- outillage

const SUPER_HOLD_STEPS := 30 # pas d'attaque tenue : 0,5 s, au-delà de super.holdTime (0,4 s)

static func _random_move(input: Dictionary, rng: Dictionary) -> Dictionary:
	var a := D6Rng.rand(rng) * PI * 2.0
	var m := D6Rng.rand(rng)
	input.moveX = cos(a) * m
	input.moveY = sin(a) * m
	input.aimX = D6Rng.rand(rng) * 2.0 - 1.0
	input.aimY = D6Rng.rand(rng) * 2.0 - 1.0
	return input

static func _random_input(rng: Dictionary) -> Dictionary:
	var input := _random_move(D6Game.empty_input(), rng)
	input.attack = D6Rng.rand(rng) < 0.5
	input.attackPressed = D6Rng.rand(rng) < 0.1
	input.dashPressed = D6Rng.rand(rng) < 0.04
	input.skill1Pressed = D6Rng.rand(rng) < 0.02
	input.skill2Pressed = D6Rng.rand(rng) < 0.005
	# Ultime (combat V3) : plus de bouton. Au rythme de l'ancien appui (1 % des pas, même tirage),
	# le joueur aléatoire TIENT l'attaque assez longtemps pour qu'il parte si la jauge est pleine.
	if D6Rng.rand(rng) < 0.01:
		rng.hold = SUPER_HOLD_STEPS
	if rng.get("hold", 0) > 0:
		rng.hold -= 1
		input.attack = true
	return input

## Tous les boutons pressés à la fois : le pire cas pour une pause.
static func _all_buttons(rng: Dictionary) -> Dictionary:
	var input := _random_move(D6Game.empty_input(), rng)
	input.merge({"attack": true, "attackPressed": true, "dashPressed": true, "skill1Pressed": true, "skill2Pressed": true, "skill3Pressed": true}, true)
	return input

static func _settle_choice(game: Dictionary) -> void:
	var i := 0
	while i < MAX_CHOICE_ROUNDS and game.mode == "choice":
		Bots.resolve_choice(game, "skilled")
		i += 1

## Un pas de jeu « joueur » : menus résolus, reprise après la mort, événements rendus.
static func _play_step(game: Dictionary, input: Dictionary) -> Array:
	if game.mode == "choice":
		_settle_choice(game)
	if game.mode == "dead":
		D6Game.apply_command(game, {"type": "respawn"})
	if game.mode != "play":
		return []
	D6Game.step_game(game, input)
	var events: Array = game.events.duplicate()
	game.events.clear()
	return events

## Salle d'arrivée vidée : seuls nos projectiles témoins frappent. Marquée nettoyée d'avance,
## sinon elle se termine à la première image (gel d'impact du dernier ennemi + récompense).
static func _quiet_game(seed_n: float) -> Dictionary:
	var game: Dictionary = D6Game.create_game({"seed": seed_n})
	game.enemies.clear()
	game.spawns.clear()
	game.room.waves = []
	game.room.cleared = true
	return game

static func _probe_hit(game: Dictionary) -> void:
	var p: Dictionary = game.player
	D6Projectiles.spawn_projectile(game, {"owner": "enemy", "kind": "probe", "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "r": PROBE_RADIUS, "damage": PROBE_DAMAGE, "range": 1e9})

## État complet (événements exclus) : copie profonde, comparée clé par clé, au bit près
## (le web compare les textes JSON.stringify de l'état).
static func _snapshot(game: Dictionary) -> Dictionary:
	var copie: Dictionary = game.duplicate(true)
	copie.erase("events")
	return copie

static func _hypot(dx: float, dy: float) -> float:
	return sqrt(dx * dx + dy * dy)

## Profondeur (u) d'un cercle dans un rectangle ; <= 0 si pas de chevauchement.
static func _rect_overlap(o: Dictionary, x: float, y: float, r: float) -> float:
	var cx := minf(maxf(x, o.x0), o.x1)
	var cy := minf(maxf(y, o.y0), o.y1)
	var inside: bool = x > o.x0 and x < o.x1 and y > o.y0 and y < o.y1
	if inside:
		return r + minf(minf(x - o.x0, o.x1 - x), minf(y - o.y0, o.y1 - y))
	return r - _hypot(x - cx, y - cy)

## Viole-t-il la géométrie de la salle (hors des murs ou dans un obstacle) ? Rend un message ou null.
static func _geometry_violation(room: Dictionary, x: float, y: float, r: float):
	var lo: float = room.pad + r - GEOM_EPS
	if x < lo or x > room.w - lo or y < lo or y > room.h - lo:
		return "hors des murs (%.1f, %.1f, r %s)" % [x, y, D6Js.num_str(r)]
	for o in room.obstacles:
		var depth := _rect_overlap(o, x, y, r)
		if depth > GEOM_EPS:
			return "%.1f u dans l'obstacle %s (%.1f, %.1f, r %s)" % [depth, JSON.stringify(o), x, y, D6Js.num_str(r)]
	return null

# ---------------------------------------------------------------- (g) dash

static func _dash(h) -> void:
	var game := _quiet_game(DASH_SEED)
	var p: Dictionary = game.player
	var x0: float = p.x
	var y0: float = p.y
	var dash: Dictionary = D6Game.empty_input()
	dash.dashPressed = true
	dash.moveY = -1.0 # vers le haut : la salle d'arrivée est ouverte
	D6Game.step_game(game, dash)
	h.egal(p.state, "dash", "le dash doit partir")
	h.ok(p.iframes > DT, "le dash doit accorder des i-frames (reste %s)" % str(p.iframes))
	var hp: float = p.hp
	var dodges: float = game.telemetry.dodges
	_probe_hit(game)
	D6Game.step_game(game, D6Game.empty_input())
	game.projectiles.clear()
	h.egal(p.hp, hp, "un coup pendant le dash ne doit pas retirer de PV")
	h.egal(game.telemetry.dodges, dodges + 1.0, "le coup évité doit être compté comme esquive (télémétrie)")
	h.ok(game.events.any(func(e): return e.type == "dodge"), "le coup évité doit émettre l'événement 'dodge'")
	var i := 0
	while i < DASH_MAX_STEPS and p.state == "dash":
		D6Game.step_game(game, D6Game.empty_input())
		i += 1
	var moved := _hypot(p.x - x0, p.y - y0)
	var d: float = game.tuning.dash.distance
	h.ok(absf(moved - d) <= d * DASH_DISTANCE_TOLERANCE, "le dash doit parcourir ~%s u (mesuré %.1f u)" % [D6Js.num_str(d), moved])

# ---------------------------------------------------------------- (h) pause des menus

static func _reach_choice(h, seed_n: float) -> Dictionary:
	var game: Dictionary = D6Game.create_game({"seed": seed_n})
	var mem := {}
	var i := 0
	while i < MENU_SEARCH_STEPS and game.mode == "play":
		D6Game.step_game(game, Bots.play("skilled", game, mem))
		game.events.clear()
		i += 1
	h.egal(game.mode, "choice", "le bot doit atteindre un menu (récompense de salle)")
	return game

static func _pause_totale(h) -> void:
	var game := _reach_choice(h, MENU_SEED)
	var before := _snapshot(game)
	var rng: Dictionary = D6Rng.create_rng(MENU_RNG_SEED)
	for i in MENU_PAUSE_STEPS:
		D6Game.step_game(game, _all_buttons(rng))
		h.egal(game.events.size(), 0, "pas %d : événement émis pendant un menu (%s)" % [i, ", ".join(PackedStringArray(game.events.map(func(e): return str(e.type))))])
	h.egal(_snapshot(game), before, "l'état a changé pendant un menu (entrées lues, gadget tiré, temps écoulé…)")

# ---------------------------------------------------------------- (i) empreinte

static func _mutations() -> Array:
	return [
		["héros déplacé de 1 u", func(g): g.player.x += 1.0],
		["PV du héros -1", func(g): g.player.hp -= 1.0],
		["PV d'un ennemi -1", func(g): g.enemies[0].hp -= 1.0],
		["RNG gen avancé", func(g): g.rng.gen.s = D6Js.u32(int(g.rng.gen.s) + 1)],
		["RNG combat avancé", func(g): g.rng.combat.s = D6Js.u32(int(g.rng.combat.s) + 1)],
		["RNG ai avancé", func(g): g.rng.ai.s = D6Js.u32(int(g.rng.ai.s) + 1)],
		["temps +1 pas", func(g): g.time += DT],
		["étage +1", func(g): g.run.floor += 1.0],
		["or +1", func(g): g.run.gold += 1.0],
	]

static func _empreinte_sensible(h) -> void:
	var base: Dictionary = D6Game.create_game({"seed": HASH_SEED})
	var i := 0
	while i < HASH_SEARCH_STEPS and base.enemies.size() == 0:
		_play_step(base, D6Game.empty_input())
		i += 1
	if not h.ok(base.enemies.size() > 0, "il faut un ennemi présent pour tester son empreinte"):
		return
	var h0 := D6Game.state_hash(base)
	for m in _mutations():
		var g: Dictionary = D6Js.clone(base)
		m[1].call(g)
		h.different(D6Game.state_hash(g), h0, "stateHash ne voit pas : %s" % m[0])

# ---------------------------------------------------------------- (k) invariants stricts

static func _check_strict_player(h, game: Dictionary, where: String) -> void:
	var p: Dictionary = game.player
	var pv = _geometry_violation(game.room, p.x, p.y, p.r)
	h.ok(pv == null, "%s : héros %s" % [where, str(pv)])
	h.ok(p.hp >= 0.0 and p.hp <= p.maxHp, "%s : PV du héros hors bornes (%s / %s)" % [where, str(p.hp), str(p.maxHp)])
	h.egal(p.hp <= 0.0, p.state == "dead", "%s : PV %s incohérents avec l'état '%s'" % [where, str(p.hp), p.state])
	h.ok(p.dashCharges >= 0.0 and p.dashCharges <= D6Player.max_dash_charges(game), "%s : charges de dash %s" % [where, str(p.dashCharges)])
	h.ok(p.slots.all(func(s): return s.charges >= 0.0), "%s : charges de gadget négatives (%s)" % [where, str(p.slots)])
	h.ok(p.superCharge >= 0.0 and p.superCharge <= 1.0, "%s : jauge de Super %s" % [where, str(p.superCharge)])

static func _check_strict(h, game: Dictionary, where: String, cover: Dictionary) -> void:
	var room: Dictionary = game.room
	_check_strict_player(h, game, where)
	for e in game.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var qui := "%s : %s#%s" % [where, e.kind, D6Js.num_str(e.id)]
		var ev = _geometry_violation(room, e.x, e.y, e.r)
		h.ok(ev == null, "%s %s" % [qui, str(ev)])
		h.ok(e.hp > 0.0 and e.hp <= e.maxHp, "%s vivant avec %s / %s PV" % [qui, str(e.hp), str(e.maxHp)])
		if room.obstacles.size() > 0:
			cover.obstacleLayouts[room.layout] = true
		if D6Js.truthy(e.get("boss")):
			cover.bossSteps += 1
	for pk in game.pickups:
		var kv = _geometry_violation(room, pk.x, pk.y, pk.r)
		h.ok(kv == null, "%s : objet au sol %s %s" % [where, str(pk.kind), str(kv)])

static func _new_cover() -> Dictionary:
	return {"obstacleLayouts": {}, "bossSteps": 0, "heals": 0}

static func _count_heals(events: Array, cover: Dictionary) -> void:
	for e in events:
		if e.type == "heal" or (e.type == "pickup" and e.get("kind") == "heal"):
			cover.heals += 1

static func _couverture_obstacles(h, cover: Dictionary) -> void:
	h.ok(cover.obstacleLayouts.size() >= MIN_OBSTACLE_LAYOUTS, "couverture : dispositions à obstacles exercées = %s" % ", ".join(PackedStringArray(cover.obstacleLayouts.keys())))

static func _stricts_sections(h) -> void:
	var cover := _new_cover()
	for seed_n in SECTION_SEEDS:
		var game: Dictionary = D6Game.create_game({"seed": seed_n})
		var mem := {}
		while game.run.floor <= SECTION_FLOORS and game.tick < SECTION_TICK_CAP:
			var events := _play_step(game, Bots.play("skilled", game, mem))
			_check_strict(h, game, "skilled graine %s tick %s étage %s" % [D6Js.num_str(seed_n), D6Js.num_str(game.tick), D6Js.num_str(game.run.floor)], cover)
			_count_heals(events, cover)
	_couverture_obstacles(h, cover)
	h.ok(cover.bossSteps > 0, "couverture : un boss doit avoir été combattu")
	h.ok(cover.heals > 0, "couverture : un soin doit avoir eu lieu (le plafond des PV est-il testé ?)")

static func _stricts_aleatoires(h) -> void:
	var cover := _new_cover()
	for start_floor in RANDOM_START_FLOORS:
		for seed_n in RANDOM_SEEDS:
			var game: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": start_floor})
			var rng: Dictionary = D6Rng.create_rng(int(seed_n) * RANDOM_SEED_FACTOR + int(start_floor))
			for i in RANDOM_STEPS:
				_play_step(game, _random_input(rng))
				_check_strict(h, game, "aléatoire graine %s départ %s tick %s" % [D6Js.num_str(seed_n), D6Js.num_str(start_floor), D6Js.num_str(game.tick)], cover)
	_couverture_obstacles(h, cover)
	h.ok(cover.bossSteps > 0, "couverture : la salle du boss doit avoir été exercée")

# ---------------------------------------------------------------- (l) oracle de jouabilité honnête

static func _boss_reellement_tue(h) -> void:
	var boss_kinds: Dictionary = D6Game.create_game().tuning.boss
	var outcomes: Array = []
	for seed_n in PLAYABILITY_SEEDS:
		var r: Dictionary = Episode.run_episode("skilled", seed_n, {"floors": SECTION_FLOORS, "minutes": PLAYABILITY_MINUTES})
		outcomes.append("graine %s : %s, étage %s" % [D6Js.num_str(seed_n), r.outcome, D6Js.num_str(r.floorReached)])
		if not r.sectionCleared:
			continue
		var boss_kills: Array = r.killTimes.filter(func(k): return boss_kinds.has(k.kind))
		h.egal(boss_kills.size(), 1, "graine %s : section battue sans tuer le boss (%s)" % [D6Js.num_str(seed_n), JSON.stringify(r.killTimes.map(func(k): return k.kind))])
		h.ok(float(D6Js.nz(r.get("bossFightSeconds"), 0.0)) > 0.0, "graine %s : durée du combat de boss absente" % D6Js.num_str(seed_n))
		return
	h.ok(false, "aucune graine ne bat la section 1 :\n  %s" % "\n  ".join(PackedStringArray(outcomes)))

# ---------------------------------------------------------------- (m) récompense atteignable

static func _clear_room(game: Dictionary) -> void:
	game.enemies.clear()
	game.spawns.clear()
	game.room.waveIndex = float(game.room.waves.size() - 1)
	D6Game.step_game(game, D6Game.empty_input())
	game.events.clear()

static func _cell_free(game: Dictionary, c: int, r: int) -> bool:
	return not D6Physics.point_blocked(game.room, (c + 0.5) * PATH_CELL, (r + 0.5) * PATH_CELL, game.player.r)

static func _cell_touches(game: Dictionary, c: int, r: int) -> bool:
	var it: Dictionary = game.room.interact
	return _hypot((c + 0.5) * PATH_CELL - it.x, (r + 0.5) * PATH_CELL - it.y) < game.player.r + it.r

## Recherche en largeur sur une grille : le héros peut-il MARCHER jusqu'à toucher l'objet ?
static func _path_to_interact(game: Dictionary) -> bool:
	var room: Dictionary = game.room
	var p: Dictionary = game.player
	var cols := int(ceilf(room.w / PATH_CELL))
	var rows := int(ceilf(room.h / PATH_CELL))
	var start := [int(floorf(p.x / PATH_CELL)), int(floorf(p.y / PATH_CELL))]
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var queue: Array = [start]
	seen[start[1] * cols + start[0]] = 1
	var head := 0
	while head < queue.size():
		var c: int = queue[head][0]
		var r: int = queue[head][1]
		if _cell_touches(game, c, r):
			return true
		for d in PATH_NEIGHBOURS:
			var nc: int = c + d[0]
			var nr: int = r + d[1]
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows or seen[nr * cols + nc] != 0 or not _cell_free(game, nc, nr):
				continue
			seen[nr * cols + nc] = 1
			queue.append([nc, nr])
		head += 1
	return false

static func _layout_sample(h, seed_n: float, start_floor: float):
	var game: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": start_floor})
	var layout = game.room.layout
	_clear_room(game)
	if not h.ok(game.room.interact != null, "graine %s étage %s (%s) : la salle nettoyée doit poser sa récompense" % [D6Js.num_str(seed_n), D6Js.num_str(start_floor), str(layout)]):
		return null
	return {"layout": layout, "seed": seed_n, "reachable": _path_to_interact(game), "at": [game.room.interact.x, game.room.interact.y]}

static func _dispositions(h) -> void:
	var seen := {}
	var seed_i := 1
	while seed_i <= LAYOUT_SEED_LIMIT and seen.size() < EXPECTED_LAYOUTS.size() - 1:
		var layout = D6Game.create_game({"seed": float(seed_i), "startFloor": LAYOUT_FLOOR}).room.layout
		if not seen.has(layout):
			seen[layout] = _layout_sample(h, float(seed_i), LAYOUT_FLOOR)
		seed_i += 1
	seen["boss"] = _layout_sample(h, 1.0, BOSS_FLOOR)
	var missing: Array = EXPECTED_LAYOUTS.filter(func(l): return not seen.has(l))
	h.egal(missing, [], "dispositions jamais tirées (non testées) : %s" % ", ".join(PackedStringArray(missing)))
	var blocked: Array = []
	for v in seen.values():
		if v != null and not v.reachable:
			blocked.append("%s (graine %s, objet en %s, %s)" % [v.layout, D6Js.num_str(v.seed), D6Js.num_str(D6Js.jround(v.at[0])), D6Js.num_str(D6Js.jround(v.at[1]))])
	h.egal(blocked, [], "récompense hors d'atteinte => portes jamais ouvertes : %s" % " ; ".join(PackedStringArray(blocked)))

# ---------------------------------------------------------------- (n) les bots ne trichent pas

## Le web enveloppe la partie dans un Proxy qui note chaque LECTURE et refuse toute ÉCRITURE.
## GDScript n'a pas de Proxy : seule la moitié « le bot n'écrit pas » se porte, en comparant
## l'empreinte récursive de TOUT l'état (Dictionary.hash) avant et après chaque décision du bot.
static func _audit_ecritures(h, policy_name: String) -> void:
	var game: Dictionary = D6Game.create_game({"seed": AUDIT_SEED})
	var mem := {}
	var ecritures := 0
	var ennemis_vus := false
	for i in AUDIT_STEPS:
		var avant := game.hash()
		var input: Dictionary = Bots.play(policy_name, game, mem)
		if game.hash() != avant:
			ecritures += 1
		ennemis_vus = ennemis_vus or game.enemies.size() > 0
		_play_step(game, input)
	h.egal(ecritures, 0, "%s ÉCRIT dans l'état de la partie (%d décisions sur %d)" % [policy_name, ecritures, AUDIT_STEPS])
	h.ok(ennemis_vus, "%s : l'audit doit avoir observé des ennemis" % policy_name)

static func _bots_honnetes(h) -> void:
	for policy_name in Bots.POLICIES:
		_audit_ecritures(h, policy_name)
	h.non_portable("moitié LECTURE (FORBIDDEN_READS : game.rng, game.nextId, enemies[].cooldown…) : le web note chaque champ lu par un Proxy récursif, sans équivalent en GDScript ; la moitié ÉCRITURE est portée ci-dessus")
