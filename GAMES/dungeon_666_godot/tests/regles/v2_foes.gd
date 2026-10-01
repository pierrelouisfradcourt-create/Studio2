extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_foes.test.mjs.
## Lot « BESTIAIRE » (V2) — archétype de ZONE (Pyromancienne, flaques persistantes), INVOCATEUR
## (Nécromancien, plafond d'invocations), champions V2 (vampirique, bouclier, invocateur),
## lisibilité (télégraphe avant tout dégât, aucun dégât de contact), déterminisme et invariants
## avec le nouveau bestiaire en jeu.
## Des lois plutôt que des valeurs : les seuils et durées lisent game.tuning.

const Bots = preload("res://outils/bots/bots.gd")

const DT := 1.0 / 60.0
const SEC := 60 # pas par seconde
const MIN_TELEGRAPH := 0.4 # s : un coup doit être précédé d'un télégraphe rouge au moins aussi long
const TELEGRAPH_LOOKBACK := 4 # s : fenêtre où chercher ce télégraphe avant le coup
const FLOOR_SEEDS := 60 # valeur web : 60
const SECTION_LAST_COMBAT := 17
const EXPECTED_KINDS := ["imp", "brute", "archer", "charger", "exploder", "pyromancer", "necromancer"]
const NEW_MODS := ["vampirique", "bouclier", "invocateur"]
const BIG_HP := 5000.0
const HIGH_FLOOR := 600.0
const INVARIANT_SEEDS := [1.0, 2.0, 3.0] # valeur web : [1, 2, 3]
const INVARIANT_START := 8.0
const INVARIANT_STEPS := 4000
const GEOM_EPS := 0.5
const FAST_RECHARGE := 0.3 # s : recharge d'invocateur volontairement courte (test du plafond)
const APPROACH_STOP := 36.0 # u entre les centres : au contact
const MELEE := ["imp", "brute", "charger", "exploder"]

# ---------------------------------------------------------------- outillage

## Salle vidée et « hors combat » (jamais nettoyée : les flaques ne s'éteignent pas d'office),
## héros immobile au centre bas. Les ennemis du test sont posés à la main.
static func _quiet_game(opts: Dictionary = {}) -> Dictionary:
	var game: Dictionary = D6Game.create_game({
		"seed": D6Js.nz(opts.get("seed"), 1.0), "godMode": D6Js.truthy(opts.get("godMode")),
		"tuning": opts.get("tuning"), "startFloor": opts.get("startFloor"),
	})
	game.enemies.clear()
	game.spawns.clear()
	game.hazards.clear()
	game.projectiles.clear()
	game.room.waves = []
	game.room.kind = "event"
	game.room.obstacles = []
	game.events.clear()
	var p: Dictionary = game.player
	p.x = game.room.w / 2.0
	p.y = game.room.h * 0.62
	if D6Js.truthy(opts.get("bigHp")):
		p.maxHp = BIG_HP
		p.hp = BIG_HP
	return game

## Avance d'un pas ; rend les événements de l'image (vidés de la partie).
static func _step(game: Dictionary, input = null) -> Array:
	D6Game.step_game(game, input if input != null else D6Game.empty_input())
	var ev: Array = game.events.duplicate()
	game.events.clear()
	return ev

## `cond` : Callable() -> bool (la partie est capturée par la lambda).
static func _step_until(game: Dictionary, cond: Callable, max_steps: int, input = null) -> Dictionary:
	var all: Array = []
	for i in max_steps:
		if D6Js.truthy(cond.call()):
			return {"ok": true, "events": all}
		all.append_array(_step(game, input))
	return {"ok": D6Js.truthy(cond.call()), "events": all}

static func _spawn_foe(game: Dictionary, kind: String, dx: float, dy: float, opts: Dictionary = {}) -> Dictionary:
	var p: Dictionary = game.player
	var o := {"spawnT": 0.0}
	o.merge(opts, true)
	var e: Dictionary = D6Enemies.create_enemy(game, kind, p.x + dx, p.y + dy, o)
	game.events.clear()
	return e

static func _hypot(dx: float, dy: float) -> float:
	return sqrt(dx * dx + dy * dy)

static func _dist(a: Dictionary, b: Dictionary) -> float:
	return _hypot(a.x - b.x, a.y - b.y)

## Champ numérique, 0 s'il est absent (undefined > 0 est faux en JavaScript).
static func _num(d: Dictionary, k: String) -> float:
	return float(D6Js.nz(d.get(k), 0.0))

static func _iter(x: float) -> int:
	return int(ceilf(x))

## Le héros marche vers l'ennemi le plus proche jusqu'à `stop_at` u, sans frapper (un joueur qui
## s'approche). Immobile, il ne serait jamais pris par un diablotin : celui-ci tourne autour à
## distance tant que le héros ne vient pas à lui (comportement d'origine de enemies.mjs).
static func _approach_input(game: Dictionary, stop_at: float) -> Dictionary:
	var p: Dictionary = game.player
	var input: Dictionary = D6Game.empty_input()
	var best = null
	for e in game.enemies:
		if not e.dead and (best == null or _dist(p, e) < _dist(p, best)):
			best = e
	if best != null and _dist(p, best) > stop_at:
		var d := _dist(p, best)
		input.moveX = (best.x - p.x) / d
		input.moveY = (best.y - p.y) / d
	return input

static func _foe_input(game: Dictionary, kind: String) -> Dictionary:
	return _approach_input(game, APPROACH_STOP) if MELEE.has(kind) else D6Game.empty_input()

## Un télégraphe ROUGE (qui fait mal) est-il visible à l'écran ?
static func _red_telegraph_visible(game: Dictionary) -> bool:
	for e in game.enemies:
		if not e.dead and e.get("tele") != null and not D6Js.truthy(e.tele.get("harmless")):
			return true
	for hz in game.hazards:
		if not D6Js.truthy(hz.get("done")) and D6Js.truthy(hz.get("hitsPlayer")) and not D6Js.truthy(hz.get("burning")):
			return true
	return false

static func _has_pyre(game: Dictionary) -> bool:
	return game.hazards.any(func(hz): return hz.get("kind") == "pyre")

static func _any_burning(game: Dictionary) -> bool:
	return game.hazards.any(func(hz): return D6Js.truthy(hz.get("burning")))

static func _kill_or_stun(game: Dictionary, e: Dictionary, how: String, stun: float) -> void:
	if how == "kill":
		D6Combat.kill_enemy(game, e, {"kind": "melee"})
	else:
		D6Combat.damage_enemy(game, e, {"kind": "wall", "amount": 1.0, "stun": stun, "canCrit": false})

## Plus longue suite continue de télégraphe visible dans la fenêtre précédant le coup (en pas).
static func _longest_run(visible: Array) -> int:
	var from: int = maxi(0, visible.size() - TELEGRAPH_LOOKBACK * SEC)
	var run := 0
	var best := 0
	for k in range(from, visible.size()):
		run = run + 1 if visible[k] else 0
		best = maxi(best, run)
	return best

# ---------------------------------------------------------------- présence dans le jeu

static func _first_floors() -> Dictionary:
	var first := {}
	for seed in range(1, FLOOR_SEEDS + 1):
		for fl in range(1, SECTION_LAST_COMBAT + 1):
			var g: Dictionary = D6Game.create_game({"seed": float(seed), "startFloor": float(fl)})
			for wave in g.room.waves:
				for s in wave:
					first[s.kind] = minf(first.get(s.kind, INF), float(fl))
	return first

static func _t_bestiaire(h) -> void:
	var first := _first_floors()
	for kind in EXPECTED_KINDS:
		h.ok(is_finite(first.get(kind, INF)), "archétype jamais tiré dans la 1re section : %s" % kind)
	for r in D6Data.tables().foe_data.EXTRA_ROSTER:
		var f: float = first.get(r.kind, INF)
		h.ok(f >= r.minIndex, "%s apparaît à l'étage %s, avant son minIndex %s" % [r.kind, f, r.minIndex])
	# Demande : zone vers l'étage 5-7, invocateur vers 8-10.
	var pyro: float = first.get("pyromancer", INF)
	var necro: float = first.get("necromancer", INF)
	h.ok(pyro >= 5.0 and pyro <= 7.0, "zone introduite à l'étage %s" % pyro)
	h.ok(necro >= 8.0 and necro <= 10.0, "invocateur introduit à l'étage %s" % necro)
	# Sections suivantes : tout le bestiaire dès le 1er étage.
	var sec2 := {}
	for seed in range(1, FLOOR_SEEDS + 1):
		for w in D6Game.create_game({"seed": float(seed), "startFloor": 19.0}).room.waves:
			for s in w:
				sec2[s.kind] = true
	h.ok(sec2.has("pyromancer") and sec2.has("necromancer"), "section 2, étage 1 : %s" % ", ".join(sec2.keys()))

static func _t_dessin_noms(h) -> void:
	var g: Dictionary = D6Game.create_game()
	for kind in D6Data.tables().foe_data.EXTRA_ENEMIES.keys():
		h.ok(g.tuning.enemies[kind].get("name"), "pas de nom pour %s" % kind)
	h.non_portable("FOE_ART, FOE_BODY, ELITE_COLORS, ELITE_NAMES viennent de src/render (dessin web) ; seule l'affirmation sur le nom (tuning) est portée")

# ---------------------------------------------------------------- lisibilité commune

static func _telegraph_case(h, kind: String) -> void:
	var g := _quiet_game({"bigHp": true})
	_spawn_foe(g, kind, 4.0, -4.0)
	var visible: Array = [] # historique : télégraphe rouge visible à chaque pas
	var hurts := 0
	for i in 10 * SEC:
		visible.append(_red_telegraph_visible(g))
		for ev in _step(g, _foe_input(g, kind)):
			if ev.type != "playerHurt":
				continue
			hurts += 1
			var best := _longest_run(visible)
			h.ok(best * DT >= MIN_TELEGRAPH, "%s : coup (%s) sans télégraphe rouge d'au moins %s s (vu %.2f s)" % [kind, ev.get("source"), MIN_TELEGRAPH, best * DT])
	if kind != "necromancer" and kind != "exploder":
		h.ok(hurts > 0, "%s : témoin — il doit avoir frappé en 10 s" % kind)

static func _t_lisibilite(h) -> void:
	for kind in EXPECTED_KINDS:
		_telegraph_case(h, kind)

static func _t_necro_ne_frappe_pas(h) -> void:
	var g := _quiet_game({"bigHp": true, "tuning": {"enemies": {"necromancer": {"maxMinions": 0.0}}}})
	_spawn_foe(g, "necromancer", 2.0, -2.0)
	var hp: float = g.player.hp
	for i in 10 * SEC:
		_step(g)
	h.egal(g.player.hp, hp)
	h.egal(D6AiCommon.summoned_count(g), 0.0)

# ---------------------------------------------------------------- Pyromancienne (zone)

## Joue jusqu'au premier allumage ; rend {attackEv, fired}.
static func _pyro_until_fire(h, g: Dictionary) -> Dictionary:
	var seen := {} # id de zone -> pas d'apparition
	var hp0: float = g.player.hp
	var st := {"attackEv": false, "fired": false}
	var i := 0
	while i < 8 * SEC and not st.fired:
		for ev in _step(g):
			if ev.type == "enemyAttack" and ev.get("enemy") == "pyromancer":
				st.attackEv = true
			if ev.type == "hazardFire" and ev.get("kind") == "pyre":
				st.fired = true
			if ev.type == "playerHurt":
				h.egal(ev.get("source"), "pyre")
				h.ok(g.hazards.any(func(hz): return hz.get("kind") == "pyre" and D6Js.truthy(hz.get("burning"))), "dégât reçu sans cercle allumé")
		for hz in g.hazards:
			if hz.get("kind") == "pyre" and not seen.has(hz.id):
				seen[hz.id] = g.tick
		if not st.fired:
			h.egal(g.player.hp, hp0, "aucun dégât avant le premier allumage")
		i += 1
	return st

static func _t_pyro_cercles(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pyromancer
	_spawn_foe(g, "pyromancer", 0.0, -def.preferredDist)
	var st := _pyro_until_fire(h, g)
	h.ok(st.attackEv, "son / événement d'attaque à l'apparition des cercles")
	h.ok(st.fired, "un cercle doit s'allumer")
	var pyres: Array = g.hazards.filter(func(hz): return hz.get("kind") == "pyre")
	h.egal(pyres.size(), def.pyre.count, "nombre de cercles d'une incantation")
	for hz in pyres:
		h.ok(hz.delay >= def.pyre.delay, "télégraphe %s s" % hz.delay)
		h.ok(hz.delay >= MIN_TELEGRAPH)
		h.ok(D6Js.truthy(hz.get("hitsPlayer")) and not D6Js.truthy(hz.get("hitsEnemies")))
		h.ok(_num(hz, "sourceId") > 0.0, "le cercle est lié à sa lanceuse (sa mort l'annule)")
	# Un cercle SUR le héros (là où il était à l'incantation : il n'a pas bougé), les autres autour.
	var on_hero: Array = pyres.filter(func(hz): return _hypot(hz.x - g.player.x, hz.y - g.player.y) < 1.0)
	h.egal(on_hero.size(), 1, "un cercle centré sur le héros")

static func _pyre_delays(h, floor_num: float) -> Array:
	var g := _quiet_game({"startFloor": floor_num, "bigHp": true})
	_spawn_foe(g, "pyromancer", 0.0, -300.0)
	var r := _step_until(g, func(): return _has_pyre(g), 8 * SEC)
	h.ok(r.ok, "étage %s : la Pyromancienne doit incanter" % floor_num)
	var delays: Array = g.hazards.filter(func(hz): return hz.get("kind") == "pyre").map(func(hz): return hz.delay)
	delays.sort()
	return delays

static func _t_pyro_telegraphe_constant(h) -> void:
	h.egal(_pyre_delays(h, 1.0), _pyre_delays(h, HIGH_FLOOR))

static func _pyro_cancel_case(h, how: String) -> void:
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, "pyromancer", 0.0, -300.0)
	var r := _step_until(g, func(): return _has_pyre(g), 8 * SEC)
	h.ok(r.ok)
	_kill_or_stun(g, e, how, 2.0)
	var hp: float = g.player.hp
	var cancels := 0
	for i in 2 * SEC:
		for ev in _step(g):
			h.ok(not (ev.type == "hazardFire" and ev.get("kind") == "pyre"), "%s : un cercle s'est allumé" % how)
			if ev.type == "hazardCancel":
				cancels += 1
	h.egal(g.player.hp, hp, "%s : dégâts reçus" % how)
	h.ok(cancels >= 1, "%s : annulation visible (hazardCancel)" % how)
	h.ok(not _any_burning(g), "%s : flaque restée au sol" % how)

static func _t_pyro_annulation(h) -> void:
	for how in ["kill", "stun"]:
		_pyro_cancel_case(h, how)

# ---------------------------------------------------------------- flaque persistante

static func _puddle_run(offset: float) -> Dictionary:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pyromancer
	var p: Dictionary = g.player
	var hz: Dictionary = D6FoePyromancer.spawn_pyre(g, p.x + offset, p.y, def, null, def.pyre.delay)
	# Temps de JEU (game.time) : le gel d'impact fige la scène sans faire avancer la flaque.
	var hurts: Array = []
	var ignited_at := -1.0
	var seen_at: float = g.time
	var total := int(ceilf((def.pyre.delay + def.pyre.linger + 2.0) * SEC))
	var last_burning := -1.0
	for i in total:
		for ev in _step(g):
			if ev.type == "hazardFire" and ev.get("id") == hz.id:
				ignited_at = g.time
			if ev.type == "playerHurt":
				hurts.append({"time": g.time, "ev": ev, "inside": _hypot(p.x - hz.x, p.y - hz.y) < hz.r + p.r})
		if D6Js.truthy(hz.get("burning")) and not hz.done:
			last_burning = g.time
	return {"g": g, "h": hz, "def": def, "hurts": hurts, "ignitedAt": ignited_at, "seenAt": seen_at, "lastBurning": last_burning}

static func _in_list(arr: Array, d: Dictionary) -> bool:
	for x in arr:
		if is_same(x, d):
			return true
	return false

static func _t_flaque_duree(h) -> void:
	var r := _puddle_run(0.0)
	var def: Dictionary = r.def
	h.ok(r.ignitedAt > 0.0, "la flaque doit s'allumer")
	h.ok(r.ignitedAt - r.seenAt >= def.pyre.delay - DT, "allumée %.2f s après son apparition (télégraphe %s s)" % [r.ignitedAt - r.seenAt, def.pyre.delay])
	var burned: float = r.lastBurning - r.ignitedAt
	h.ok(absf(burned - def.pyre.linger) <= 2.0 * DT, "durée de la flaque %.2f s (attendu %s)" % [burned, def.pyre.linger])
	h.ok(r.h.done and not _in_list(r.g.hazards, r.h), "la flaque éteinte quitte la liste des zones")

static func _t_flaque_degats(h) -> void:
	var inside := _puddle_run(0.0)
	var pyre_hurts: Array = inside.hurts.filter(func(x): return x.ev.get("source") == "pyre")
	h.ok(pyre_hurts.size() >= 2, "dedans : impact puis brûlure attendus (%d coups)" % pyre_hurts.size())
	for x in pyre_hurts:
		h.ok(x.inside, "dégât de flaque reçu hors de la flaque")
		h.ok(x.time >= inside.ignitedAt, "dégât de flaque avant son allumage")
	# Après l'impact : des ticks espacés d'au moins tickEvery.
	var tk: Array = pyre_hurts.slice(1)
	for i in range(1, tk.size()):
		h.ok(tk[i].time - tk[i - 1].time >= inside.def.pyre.tickEvery - DT)
	var p: Dictionary = inside.g.player
	var outside := _puddle_run(inside.h.r + p.r + 2.0)
	h.egal(outside.hurts.size(), 0, "juste hors de la flaque : aucun dégât")

static func _t_flaque_salle_nettoyee(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pyromancer
	var hz: Dictionary = D6FoePyromancer.spawn_pyre(g, g.player.x + 300.0, g.player.y, def, null, def.pyre.delay)
	_step_until(g, func(): return D6Js.truthy(hz.get("burning")), 3 * SEC)
	h.ok(hz.get("burning"))
	g.room.cleared = true
	_step(g)
	h.ok(hz.done)

static func _t_bot_contourne(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pyromancer
	var p: Dictionary = g.player
	# Hors combat, le bot veut aller au centre de la salle : la flaque y brûle.
	p.x = g.room.w / 2.0
	p.y = g.room.h / 2.0 + 250.0
	var hz: Dictionary = D6FoePyromancer.spawn_pyre(g, g.room.w / 2.0, g.room.h / 2.0, def, null, 0.0)
	_step(g) # allumage (le héros est loin : aucun dégât)
	h.ok(hz.get("burning"))
	var mem := {}
	var inside := 0
	var closest := INF
	var i := 0
	while i < _iter(def.pyre.linger * SEC) and not hz.done:
		_step(g, Bots.play("skilled", g, mem))
		var d := _hypot(p.x - hz.x, p.y - hz.y)
		closest = minf(closest, d)
		if d < hz.r + p.r:
			inside += 1
		i += 1
	h.egal(inside, 0, "le bot est entré dans la flaque")
	h.ok(closest < hz.r + p.r + 60.0, "témoin : le bot doit s'être approché du bord (au plus près %.0f u)" % closest)

static func _t_bot_sort_de_flaque(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pyromancer
	var p: Dictionary = g.player
	p.x = g.room.w / 2.0
	p.y = g.room.h / 2.0
	var hz: Dictionary = D6FoePyromancer.spawn_pyre(g, p.x, p.y, def, null, 0.0)
	var impact: Array = _step(g).filter(func(ev): return ev.type == "playerHurt")
	h.egal(impact.size(), 1, "l'allumage frappe le héros dedans")
	var mem := {}
	var i := 0
	while i < _iter(def.pyre.linger * SEC) and not hz.done:
		for ev in _step(g, Bots.play("skilled", g, mem)):
			h.different(ev.type, "playerHurt", "brûlure reprise : le bot est resté dans la flaque")
		i += 1

# ---------------------------------------------------------------- Nécromancien (invocateur)

## 25 s d'invocations ; rend {maxCount, channelSeen, warns, summoned}.
static func _necro_watch(h, g: Dictionary, e: Dictionary, def: Dictionary) -> Dictionary:
	var st := {"maxCount": 0.0, "channelSeen": false, "warns": 0, "summoned": 0}
	for i in 25 * SEC:
		for ev in _step(g):
			if ev.type == "spawnWarn":
				st.warns += 1
			if ev.type == "spawn" and ev.get("enemy") == def.minionKind:
				st.summoned += 1
		if e.state == "channel":
			st.channelSeen = true
			h.ok(e.get("tele") != null and e.tele.get("harmless") == true, "la canalisation est une alerte inoffensive (violette)")
		var n: float = D6AiCommon.summoned_count(g)
		st.maxCount = maxf(st.maxCount, n)
		h.ok(n <= def.maxMinions, "plafond dépassé : %s > %s" % [n, def.maxMinions])
		for o in g.enemies:
			if D6Js.truthy(o.get("summoned")):
				h.egal(o.kind, def.minionKind)
		# Les invocations meurent en route : on les abat pour vérifier qu'il en rappelle d'autres.
		if i == 12 * SEC:
			for o in g.enemies.duplicate():
				if D6Js.truthy(o.get("summoned")):
					D6Combat.kill_enemy(g, o, {"kind": "melee"})
	return st

static func _t_necro_plafond(h) -> void:
	# Recharge très courte : sans plafond, il dépasserait largement maxMinions en 25 s.
	var g := _quiet_game({"godMode": true, "tuning": {"enemies": {"necromancer": {"cooldown": FAST_RECHARGE}}}})
	var def: Dictionary = g.tuning.enemies.necromancer
	var e := _spawn_foe(g, "necromancer", 0.0, -380.0)
	var st := _necro_watch(h, g, e, def)
	h.ok(st.channelSeen, "canalisation observée")
	h.egal(st.maxCount, def.maxMinions, "il remplit son plafond")
	h.ok(st.warns >= st.summoned and st.summoned > def.maxMinions, "cercles %d, invocations %d (il en rappelle après leur mort)" % [st.warns, st.summoned])
	# Les invocations ne rapportent ni or ni Âmes (pas de ferme).
	var g2 := _quiet_game({"godMode": true})
	var imp: Dictionary = D6Enemies.create_enemy(g2, "imp", 100.0, 100.0, {"spawnT": 0.0, "summoned": true})
	var souls: float = g2.meta.souls
	D6Combat.kill_enemy(g2, imp, {"kind": "melee"})
	h.egal(g2.meta.souls, souls)
	h.egal(g2.pickups.size(), 0)

static func _necro_cancel_case(h, how: String) -> void:
	var g := _quiet_game({"godMode": true})
	var def: Dictionary = g.tuning.enemies.necromancer
	var e := _spawn_foe(g, "necromancer", 0.0, -380.0)
	var r := _step_until(g, func(): return e.state == "channel" and e.stateTime > def.channel * 0.5, 10 * SEC)
	h.ok(r.ok, "il doit canaliser")
	var stun := 1.5
	_kill_or_stun(g, e, how, stun)
	# Fenêtre : le reste de la canalisation + l'alerte des cercles (et l'étourdissement).
	var window: float = (stun if how == "stun" else 0.0) + def.channel
	for i in _iter(window * SEC):
		for ev in _step(g):
			h.different(ev.type, "spawnWarn", "%s : un cercle d'invocation s'est ouvert" % how)
	h.egal(g.spawns.size(), 0)
	h.egal(D6AiCommon.summoned_count(g), 0.0)

static func _t_necro_annulation(h) -> void:
	for how in ["kill", "stun"]:
		_necro_cancel_case(h, how)

# ---------------------------------------------------------------- champions V2

static func _t_elite_bouclier(h) -> void:
	var g := _quiet_game({"godMode": true})
	var m: Dictionary = g.tuning.elite.mods.bouclier
	var e := _spawn_foe(g, "brute", 0.0, -500.0, {"elite": "bouclier"})
	var hit := func(): return D6Combat.damage_enemy(g, e, {"kind": "wall", "amount": 1.0, "canCrit": false})
	h.ok(hit.call() > 0.0, "vulnérable au départ")
	var c := {"warn": 0}
	var r := _step_until(g, func():
		if e.get("modPhase") == "warn":
			c.warn += 1
		return _num(e, "invuln") > 0.0, 10 * SEC)
	h.ok(r.ok, "la bulle doit se lever")
	h.ok(c.warn * DT >= m.warn - 2.0 * DT, "annonce trop courte : %.2f s" % (c.warn * DT))
	var hp: float = e.hp
	h.egal(hit.call(), 0.0, "immunisé sous la bulle")
	h.egal(e.hp, hp)
	var r2 := _step_until(g, func(): return not (_num(e, "invuln") > 0.0), _iter((m.duration + 1.0) * SEC))
	h.ok(r2.ok, "la bulle retombe")
	h.ok(hit.call() > 0.0, "vulnérable de nouveau")

static func _vampire_case(h, kind: String, dx: float, dy: float) -> bool:
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, kind, dx, dy, {"elite": "vampirique"})
	e.hp = floorf(e.maxHp / 2.0)
	for i in 12 * SEC:
		var before: float = e.hp
		for ev in _step(g, _foe_input(g, kind)):
			if ev.type != "playerHurt":
				continue
			var m: Dictionary = g.tuning.elite.mods.vampirique
			h.egal(e.hp, minf(e.maxHp, before + D6Js.jround(ev.amount * m.leech)), "%s : soin = leech × dégâts infligés" % kind)
			h.ok(_num(e, "leechFlash") > 0.0, "%s : drain visible" % kind)
			return true
	return false

static func _t_elite_vampirique(h) -> void:
	h.ok(_vampire_case(h, "imp", 30.0, 0.0), "diablotin (coup direct)")
	h.ok(_vampire_case(h, "brute", 40.0, 0.0), "brute (zone)")
	h.ok(_vampire_case(h, "archer", 0.0, -260.0), "archer (projectile)")
	# Un autre modificateur ne soigne pas.
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, "imp", 30.0, 0.0, {"elite": "rapide"})
	e.hp = 10.0
	for i in 6 * SEC:
		_step(g)
	h.ok(e.hp <= 10.0)

static func _summoner_cancel_case(h, how: String, m: Dictionary) -> void:
	var g2 := _quiet_game({"godMode": true})
	var e2 := _spawn_foe(g2, "archer", 0.0, -500.0, {"elite": "invocateur"})
	h.ok(_step_until(g2, func(): return e2.get("modPhase") == "channel", 10 * SEC).ok)
	var stun: float = m.channel + 0.5
	_kill_or_stun(g2, e2, how, stun)
	for i in _iter((m.channel + (stun if how == "stun" else 1.0)) * SEC):
		for ev in _step(g2):
			h.different(ev.type, "spawnWarn", "%s : un cercle s'est ouvert" % how)
	h.egal(D6AiCommon.summoned_count(g2), 0.0, how)

static func _t_elite_invocateur(h) -> void:
	var g := _quiet_game({"godMode": true})
	var m: Dictionary = g.tuning.elite.mods.invocateur
	var e := _spawn_foe(g, "imp", 0.0, -500.0, {"elite": "invocateur"})
	var channel := false
	var sound := false
	for i in 20 * SEC:
		for ev in _step(g):
			if ev.type == "enemyAttack" and ev.get("enemy") == "summon":
				sound = true
		if e.get("modPhase") == "channel":
			channel = true
		h.ok(D6AiCommon.summoned_count(g) <= m.maxMinions)
	h.ok(channel and sound, "canalisation visible et audible")
	h.egal(D6AiCommon.summoned_count(g), m.maxMinions, "plafond atteint")
	# Tué (ou étourdi) pendant sa canalisation : aucun cercle.
	for how in ["kill", "stun"]:
		_summoner_cancel_case(h, how, m)

static func _draw(g: Dictionary, kind: String, info: Dictionary, n: int = 600) -> Dictionary:
	var s := {}
	for i in n:
		s[D6FoeElites.pick_elite_mod(g, kind, info)] = true
	return s

static func _planned_elites() -> Dictionary:
	var seen := {}
	for seed in range(1, FLOOR_SEEDS * 2 + 1):
		for fl in [7.0, 11.0, 13.0, 20.0, 25.0]:
			for w in D6Game.create_game({"seed": float(seed), "startFloor": fl}).room.waves:
				for s in w:
					if D6Js.truthy(s.get("elite")):
						seen[s.elite] = true
	return seen

static func _t_modificateurs(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 9.0})
	var mods: Dictionary = g.tuning.elite.mods
	var late := _draw(g, "imp", {"section": 2.0, "indexInSection": 1.0})
	for m in mods.keys():
		h.ok(late.has(m), "section 2 : %s jamais tiré" % m)
	var early: Array = _draw(g, "imp", {"section": 1.0, "indexInSection": 3.0}).keys()
	early.sort()
	h.egal(early, ["ardent", "blinde", "rapide"], "étages 1-5 : seulement les modificateurs d'origine")
	for m in mods.keys():
		for kind in D6Js.nz(mods[m].get("excludeKinds"), []):
			h.ok(not _draw(g, kind, {"section": 3.0, "indexInSection": 10.0}).has(m), "%s ne doit jamais être %s" % [kind, m])
	# Et en vrai : les nouveaux champions sortent dans les vagues planifiées.
	var seen := _planned_elites()
	for m in NEW_MODS:
		h.ok(seen.has(m), "champion %s jamais planifié dans une vague" % m)

# ---------------------------------------------------------------- déterminisme et invariants

## `check` : Callable(game) ou null.
static func _bot_run(seed: float, start_floor: float, steps: int, check = null) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed, "startFloor": start_floor})
	var mem := {}
	for i in steps:
		var k := 0
		while k < 8 and g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
			k += 1
		if g.mode == "dead":
			D6Game.apply_command(g, {"type": "respawn"})
		if g.mode != "play":
			break
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		if check != null:
			check.call(g)
		g.events.clear()
	return g

static func _determinism_run(kinds: Dictionary) -> Array:
	var g := _bot_run(4.0, INVARIANT_START, 3000, func(gg):
		for e in gg.enemies:
			kinds[e.kind] = true)
	return [D6Game.state_hash(g), g.rng.gen.s, g.rng.combat.s, g.rng.ai.s, g.hazards.size(), g.spawns.size()]

static func _t_determinisme(h) -> void:
	var kinds := {}
	var a := _determinism_run(kinds)
	var b := _determinism_run(kinds)
	h.egal(a, b)
	h.ok(kinds.has("pyromancer") or kinds.has("necromancer"), "couverture : %s" % ", ".join(kinds.keys()))

## Profondeur (u) d'un cercle dans un rectangle ; <= 0 si pas de chevauchement.
static func _rect_overlap(o: Dictionary, x: float, y: float, r: float) -> float:
	var cx := minf(maxf(x, o.x0), o.x1)
	var cy := minf(maxf(y, o.y0), o.y1)
	var inside: bool = x > o.x0 and x < o.x1 and y > o.y0 and y < o.y1
	if inside:
		return r + minf(minf(x - o.x0, o.x1 - x), minf(y - o.y0, o.y1 - y))
	return r - _hypot(x - cx, y - cy)

## Rend "" quand tout va bien (null côté web).
static func _geometry_violation(room: Dictionary, x: float, y: float, r: float) -> String:
	var lo: float = room.pad + r - GEOM_EPS
	if x < lo or x > room.w - lo or y < lo or y > room.h - lo:
		return "hors des murs"
	for o in room.obstacles:
		if _rect_overlap(o, x, y, r) > GEOM_EPS:
			return "dans un obstacle"
	return ""

static func _invariant_check(h, g: Dictionary, cover: Dictionary) -> void:
	var p: Dictionary = g.player
	h.ok(p.hp >= 0.0 and p.hp <= p.maxHp, "PV du héros %s" % p.hp)
	for e in g.enemies:
		if e.dead:
			continue
		h.ok(e.hp > 0.0 and e.hp <= e.maxHp, "%s#%s vivant avec %s / %s" % [e.kind, e.id, e.hp, e.maxHp])
		var v := _geometry_violation(g.room, e.x, e.y, e.r)
		h.egal(v, "", "%s#%s %s (%.1f, %.1f)" % [e.kind, e.id, v, e.x, e.y])
		if e.kind == "pyromancer":
			cover.pyro += 1
		if e.kind == "necromancer":
			cover.necro += 1
		if D6Js.truthy(e.get("eliteMod")):
			cover.elites[e.eliteMod] = true
	if _any_burning(g):
		cover.puddles += 1

static func _t_invariants(h) -> void:
	var cover := {"pyro": 0, "necro": 0, "puddles": 0, "elites": {}}
	for seed in INVARIANT_SEEDS:
		_bot_run(seed, INVARIANT_START, INVARIANT_STEPS, func(g): _invariant_check(h, g, cover))
	h.ok(cover.pyro > 0 and cover.necro > 0, "couverture : pyromancienne %d, nécromancien %d" % [cover.pyro, cover.necro])
	h.ok(cover.puddles > 0, "couverture : une flaque a brûlé")

# ---------------------------------------------------------------- les tests

static func tests(h) -> void:
	h.test("bestiaire : les 7 archétypes apparaissent ; la zone puis l'invocateur entrent progressivement dans la 1re section", func(): _t_bestiaire(h))
	h.test("dessin et noms : chaque archétype ajouté a sa silhouette et sa couleur ; chaque modificateur a sa couleur et son nom", func(): _t_dessin_noms(h))
	h.test("chaque archétype, posé SUR le héros : tout dégât est précédé d'un télégraphe rouge visible — aucun dégât de contact", func(): _t_lisibilite(h))
	h.test("nécromancien : il ne frappe jamais lui-même (sans invocations, 10 s collé au héros = 0 dégât)", func(): _t_necro_ne_frappe_pas(h))
	h.test("Pyromancienne : cercles de feu télégraphiés sur et autour du héros ; aucun dégât avant l'allumage", func(): _t_pyro_cercles(h))
	h.test("Pyromancienne : télégraphe identique à l'étage 1 et à l'étage 600 (la difficulté ne le raccourcit jamais)", func(): _t_pyro_telegraphe_constant(h))
	h.test("Pyromancienne : la tuer (ou l'étourdir) pendant le télégraphe ANNULE ses cercles — ni dégât ni flaque", func(): _t_pyro_annulation(h))
	h.test("flaque : allumée SEULEMENT après son télégraphe, elle persiste `linger` s puis s'éteint", func(): _t_flaque_duree(h))
	h.test("flaque : dégâts par tick SEULEMENT à l'intérieur (héros dedans : touché plusieurs fois ; juste dehors : jamais)", func(): _t_flaque_degats(h))
	h.test("flaque : la salle nettoyée l'éteint (la récompense se ramasse sans brûler)", func(): _t_flaque_salle_nettoyee(h))
	h.test("bot skilled : une flaque allumée sur son chemin, il la contourne sans jamais y entrer", func(): _t_bot_contourne(h))
	h.test("bot skilled : pris par un allumage, il ne reprend plus aucune brûlure de cette flaque", func(): _t_bot_sort_de_flaque(h))
	h.test("Nécromancien : canalisation visible et INOFFENSIVE, cercles d'invocation, plafond d'invocations vivantes", func(): _t_necro_plafond(h))
	h.test("Nécromancien : le tuer pendant la canalisation l'annule — aucun cercle ne s'ouvre ; l'étourdir aussi", func(): _t_necro_annulation(h))
	h.test("élite bouclier : anneau d'annonce puis bulle d'immunité (coups sans effet), puis vulnérable de nouveau", func(): _t_elite_bouclier(h))
	h.test("élite vampirique : se soigne de ce qu'il inflige — coup direct, zone et projectile", func(): _t_elite_vampirique(h))
	h.test("élite invocateur : canalise (alerte inoffensive), invoque sous son plafond ; tué en canalisant, rien ne s'ouvre", func(): _t_elite_invocateur(h))
	h.test("modificateurs : tirage avec exclusions et introduction progressive ; les premiers étages gardent le tirage d'origine", func(): _t_modificateurs(h))
	h.test("déterminisme : mêmes graine et entrées => même partie, nouveaux archétypes et champions en jeu", func(): _t_determinisme(h))
	h.test("invariants stricts avec le nouveau bestiaire (bot skilled, étages 8+) : PV bornés (soins vampiriques compris), murs, obstacles", func(): _t_invariants(h))
	h.test("audio : attaques des nouveaux archétypes et allumage des flaques jouent sans erreur WebAudio", func():
		h.non_portable("teste src/audio/sfx.mjs (WebAudio simulé) : pas d'audio web sous Godot"))
