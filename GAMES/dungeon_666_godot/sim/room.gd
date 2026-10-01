class_name D6Room
extends RefCounted
## Portage de src/sim/room.mjs.
## Salles : géométrie (dispositions d'obstacles), vagues d'ennemis, apparitions,
## détection de fin de combat et portes de sortie.
##
## Une salle = un étage. Le héros entre en bas, deux portes s'ouvrent en haut une fois la
## salle nettoyée ; chacune annonce la récompense de la salle suivante (façon Hades).
##
## Les tables exportées (LAYOUTS, LAYOUT_IDS, COMBAT_LAYOUTS, BOSS_LAYOUT, ROSTER) se lisent dans
## D6Data.tables().room : dispositions d'obstacles en fractions de la salle (cx, cy, w, h en
## unités) ; coût en « budget de vague » de chaque archétype et index d'apparition minimal.

const DOOR_W := 120.0
const DOOR_H := 40.0
const REWARD_CLEARANCE := 60.0 # u libres autour d'une récompense (le héros doit pouvoir la toucher)
const WAVE_GUARD := 40.0 # garde-fou du tirage d'une vague
const ELITE_BASE_KINDS := ["brute", "charger", "imp", "archer"]
const STRAY_KINDS := ["imp", "archer"]

## Salle d'un étage, COMPOSÉE à partir du plan (run → sections compose_floor) :
## plan.kind dit le type (combat | elite | boss | shop | event | treasure | rest), plan.layouts
## les dispositions permises et leurs poids, plan.waves / budget / roster le contenu des vagues.
## Les salles calmes (marchand, autel, trésor, repos) restent dégagées.
static func build_room(game: Dictionary, info: Dictionary, plan: Dictionary) -> Dictionary:
	var t: Dictionary = game.tuning.room
	var tables: Dictionary = D6Data.tables().room
	var room := {
		"w": t.width,
		"h": t.height,
		"pad": t.wallPad,
		"kind": plan.kind, # combat | elite | shop | event | treasure | rest | boss
		"reward": plan.get("reward"), # boon | loot | gold | heal | shop | event | treasure | rest | boss
		"layout": "open",
		"obstacles": [],
		"waves": [],
		"waveIndex": -1.0,
		"cleared": false,
		"clearedAt": 0.0,
		"enteredAt": game.time,
		"doors": [],
		"interact": null, # objet à toucher : récompense, marchand, autel, coffre, fontaine
		"theme": info.circle,
	}
	var rects: Array = []
	if plan.kind == "boss":
		rects = tables.BOSS_LAYOUT
		room.layout = "boss"
	elif plan.kind == "combat" or plan.kind == "elite":
		room.layout = _pick_layout(game, info, plan.get("layouts"))
		rects = tables.LAYOUTS[room.layout]
	for rect in rects:
		var fx: float = rect[0]
		var fy: float = rect[1]
		var w: float = rect[2]
		var h: float = rect[3]
		var cx: float = fx * room.w
		var cy: float = fy * room.h
		room.obstacles.append({"x0": cx - w / 2.0, "y0": cy - h / 2.0, "x1": cx + w / 2.0, "y1": cy + h / 2.0})
	if plan.kind == "combat" or plan.kind == "elite":
		room.waves = _plan_waves(game, info, plan)
	room.nav = D6Nav.build_nav(room)
	return room

## Disposition tirée parmi celles du plan ([{id, weight}]) ; une seule = aucun tirage.
static func _pick_layout(game: Dictionary, info: Dictionary, layouts) -> String:
	var tables: Dictionary = D6Data.tables().room
	var known: Array = []
	if layouts != null:
		for l in layouts:
			if tables.LAYOUTS.has(l.id) and l.weight > 0.0:
				known.append(l)
	if known.size() == 1:
		return known[0].id
	if known.size() > 1:
		return D6Rng.weighted_pick(game.rng.gen, known, func(l): return l.weight).id
	# Repli sans plan (ancien comportement) : salle ouverte au tout premier étage.
	if info.floor == 1.0:
		return "open"
	return D6Rng.pick(game.rng.gen, tables.COMBAT_LAYOUTS)

## Point libre pour poser une récompense : le centre de la salle si possible, sinon le point
## libre le plus proche sur une spirale. Jamais dans un obstacle (sinon : partie bloquée).
static func reward_spot(room: Dictionary) -> Dictionary:
	var cx: float = room.w / 2.0
	var cy: float = room.h * 0.45
	if not D6Js.truthy(D6Physics.point_blocked(room, cx, cy, REWARD_CLEARANCE)):
		return {"x": cx, "y": cy}
	for ring in range(1, 20):
		var d: float = float(ring) * 30.0
		for k in range(16):
			var a: float = (float(k) / 16.0) * PI * 2.0 + PI / 2.0 # commence sous l'obstacle
			var x: float = cx + D6Trig.cos(a) * d
			var y: float = cy + D6Trig.sin(a) * d
			if not D6Js.truthy(D6Physics.point_blocked(room, x, y, REWARD_CLEARANCE)):
				return {"x": x, "y": y}
	return player_start(room)

static func player_start(room: Dictionary) -> Dictionary:
	return {"x": room.w / 2.0, "y": room.h - room.pad - 70.0}

## Arène d'essai : quand les vagues sont épuisées, on en replanifie (combat sans fin), d'après
## le plan d'arène préparé par run (room.refill : un étage de combat de début de section).
static func refill_sandbox_waves(game: Dictionary) -> void:
	var room: Dictionary = game.room
	var sb: Dictionary = game.tuning.section.sandbox
	var base = room.get("refill")
	if base == null:
		base = room.get("plan")
	if base == null:
		base = {}
	var elite: bool = D6Rng.rand(game.rng.gen) < sb.eliteChance
	var info: Dictionary = game.info.duplicate()
	info.floor = D6Js.nz(base.get("floor"), sb.floor)
	var plan: Dictionary = base.duplicate()
	plan.elite = elite
	room.waves = _plan_waves(game, info, plan)
	room.waveIndex = -1.0
	launch_next_wave(game)

## Vagues d'un étage de combat, d'après le plan composé : `waves` vagues de `budget` points de
## menace (la dernière × lastWaveMult), tirées dans le bestiaire pondéré `roster` du plan
## ([{kind, cost, weight}] — thème du Cercle compris). Salle d'élite : un champion en dernière
## vague ; ailleurs, un élite égaré avec la probabilité `strayEliteChance` du plan.
static func _plan_waves(game: Dictionary, info: Dictionary, plan: Dictionary) -> Array:
	var t: Dictionary = game.tuning
	var enc: Dictionary = t.encounter
	var wave_count = plan.get("waves")
	if wave_count == null:
		wave_count = t.section.paces[t.section.calmPace].waves
	var budget = plan.get("budget")
	if budget == null:
		budget = (enc.baseBudget + enc.perIndex * info.indexInSection) * D6Floors.floor_scaling(t, info.floor).density
	var roster = plan.get("roster")
	if roster == null:
		roster = D6Data.tables().room.ROSTER
	var pool: Array = []
	for r in roster:
		if t.enemies.get(r.kind) != null and r.weight > 0.0:
			pool.append(r)
	var waves: Array = []
	var w := 0.0
	while w < wave_count:
		var b: float = budget * (enc.lastWaveMult if w == wave_count - 1.0 else 1.0)
		waves.append(_plan_wave(game, pool, b))
		w += 1.0
	_plan_elite(game, info, plan, pool, waves)
	return waves

## Une vague : des archétypes tirés tant qu'il reste du budget (et au plus WAVE_GUARD tirages).
static func _plan_wave(game: Dictionary, pool: Array, budget: float) -> Array:
	var b := budget
	var wave: Array = []
	var guard := 0.0
	while b >= 1.0:
		var more := guard < WAVE_GUARD
		guard += 1.0
		if not more:
			break
		var affordable: Array = []
		for r in pool:
			if r.cost <= b:
				affordable.append(r)
		var choice = D6Rng.weighted_pick(game.rng.gen, affordable, func(r): return r.weight)
		if choice == null:
			break
		wave.append({"kind": choice.kind, "elite": null})
		b -= choice.cost
	return wave

## Champion de la salle d'élite, ou élite égaré, ajouté à la dernière vague.
static func _plan_elite(game: Dictionary, info: Dictionary, plan: Dictionary, pool: Array, waves: Array) -> void:
	var t: Dictionary = game.tuning
	var enc: Dictionary = t.encounter
	var stray = plan.get("strayEliteChance")
	if stray == null:
		stray = enc.strayEliteChance if info.floor >= enc.strayEliteFrom else 0.0
	if D6Js.truthy(plan.get("elite")):
		# Salle d'élite : un champion (modificateur façon Diablo) dans la dernière vague.
		# Le champion sort du bestiaire de l'étage : en section 1 les archétypes entrent un à un
		# (sections roster_for), une porte d'élite ne les fait pas apparaître plus tôt.
		var known: Array = []
		for k in ELITE_BASE_KINDS + D6Data.tables().foe_data.EXTRA_ELITE_KINDS:
			if t.enemies.get(k) != null:
				known.append(k)
		var no_roster: bool = plan.get("roster") == null
		var present: Array = []
		for k in known:
			if no_roster or pool.any(func(r): return r.kind == k):
				present.append(k)
		var champion = D6Rng.pick(game.rng.gen, present if present.size() > 0 else known)
		waves[waves.size() - 1].append({"kind": champion, "elite": D6FoeElites.pick_elite_mod(game, champion, info)})
	elif stray > 0.0 and D6Rng.rand(game.rng.gen) < stray:
		var kind = D6Rng.pick(game.rng.gen, STRAY_KINDS)
		waves[waves.size() - 1].append({"kind": kind, "elite": D6FoeElites.pick_elite_mod(game, kind, info)})

static func launch_next_wave(game: Dictionary) -> bool:
	var room: Dictionary = game.room
	room.waveIndex += 1.0
	var wave = _wave_at(room, room.waveIndex)
	if wave == null:
		return false
	for s in wave:
		var pt = D6Spawns.find_spawn_point(game, 30.0, game.tuning.room.spawnMinPlayerDist)
		if pt != null:
			D6Spawns.queue_spawn(game, s.kind, pt.x, pt.y, {"elite": s.elite})
	D6State.emit(game, "wave", {"index": room.waveIndex, "count": float(room.waves.size())})
	return true

## room.waves[index] de JavaScript : null hors du tableau (index -1 compris).
static func _wave_at(room: Dictionary, index):
	var i := int(index)
	if i < 0 or i >= room.waves.size():
		return null
	return room.waves[i]

## Gardien de la section (modèle du plan : rotation floors.guardian_for).
static func spawn_boss(game: Dictionary, kind = "gardien") -> void:
	var room: Dictionary = game.room
	D6Enemies.create_enemy(game, kind, room.w / 2.0, room.h * 0.35, {"boss": true, "spawnT": 1.2})

static func update_spawns(game: Dictionary, dt: float) -> void:
	var spawns: Array = game.spawns
	var w := 0
	var i := 0
	while i < spawns.size():
		var s = spawns[i]
		s.t -= dt
		if s.t <= 0.0:
			D6Enemies.create_enemy(game, s.kind, s.x, s.y, {"elite": s.get("elite"), "summoned": s.get("summoned")})
		else:
			spawns[w] = s
			w += 1
		i += 1
	spawns.resize(w)

## Vagues suivantes et fin de salle. Rend true à l'image où la salle est nettoyée.
static func update_waves(game: Dictionary) -> bool:
	var room: Dictionary = game.room
	if room.cleared:
		return false
	if room.kind != "combat" and room.kind != "elite" and room.kind != "boss":
		return false
	var alive: float = D6Enemies.alive_enemies(game)
	var pending: float = game.spawns.size()
	if room.kind == "boss":
		return _update_boss_room(game, alive, pending)
	# Vague suivante quand il ne reste presque plus personne : rythme continu.
	if room.waveIndex < room.waves.size() - 1:
		var cur = _wave_at(room, room.waveIndex)
		var cur_size: float = 0.0 if cur == null else float(cur.size())
		var threshold: float = maxf(0.0, floorf(cur_size * 0.25))
		if alive + pending <= threshold:
			launch_next_wave(game)
		return false
	return alive + pending == 0.0

## Salle du Gardien : nettoyée quand le boss est tombé (ou absent).
static func _update_boss_room(game: Dictionary, alive: float, pending: float) -> bool:
	var boss = null
	for e in game.enemies:
		if D6Js.truthy(e.get("boss")):
			boss = e
			break
	if boss != null and not D6Js.truthy(boss.get("dead")):
		return false
	if alive + pending > 0.0:
		# Le boss est tombé : ses invocations meurent avec lui.
		for e in game.enemies:
			if not D6Js.truthy(e.get("dead")):
				e.dead = true
		game.spawns.clear()
	# ... et ses attaques en cours aussi : aucun coup ne part d'un Gardien mort.
	var hazards: Array = game.hazards
	var i := 0
	while i < hazards.size():
		var h = hazards[i]
		if not D6Js.truthy(h.get("done")) and D6Js.truthy(h.get("hitsPlayer")):
			h.done = true
			D6State.emit(game, "hazardCancel", {"id": h.get("id"), "x": h.get("x"), "y": h.get("y")})
		i += 1
	for pr in game.projectiles:
		if pr.get("owner") == "enemy":
			pr.dead = true
	return true

## `descs` : [{reward, family?}] — une porte par descripteur, réparties en haut de la salle.
static func make_doors(game: Dictionary, descs: Array) -> void:
	var room: Dictionary = game.room
	var n: float = descs.size()
	var doors: Array = []
	for i in descs.size():
		var cx: float = room.w / 2.0 if n == 1.0 else room.w * (0.32 + (0.36 * float(i)) / (n - 1.0))
		var door: Dictionary = descs[i].duplicate()
		door.x = cx - DOOR_W / 2.0
		door.y = 0.0
		door.w = DOOR_W
		door.h = room.pad + DOOR_H
		door.open = true
		doors.append(door)
	room.doors = doors

## Porte touchée par le héros (son rang), ou -1.
static func door_touched(game: Dictionary) -> int:
	var p: Dictionary = game.player
	var doors: Array = game.room.doors
	for i in doors.size():
		var d = doors[i]
		if not D6Js.truthy(d.get("open")):
			continue
		if p.x > d.x and p.x < d.x + d.w and p.y - p.r < d.y + d.h:
			return i
	return -1

static func random_gold(game: Dictionary) -> float:
	var range_gold: Array = game.tuning.economy.goldPerRoom
	return D6Rng.rand_int(game.rng.gen, range_gold[0], range_gold[1])
