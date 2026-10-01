extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_foes_2.test.mjs.
## Lot « BESTIAIRE 2 » (2026-10-01) — les trois archétypes ajoutés :
##   pavois  (Porte-pavois)   : arrête les coups de face ; on le frappe de dos, de flanc, après son
##                              coup, ou étourdi ;
##   stalker (Traqueur)       : se dissout, disparaît, resurgit dans le dos du héros et frappe en
##                              cercle après un télégraphe rouge ;
##   banner  (Porte-étendard) : n'attaque jamais ; les autres ennemis sous son aura prennent moins.
## Des lois plutôt que des valeurs : les seuils et durées lisent game.tuning.

const Bots = preload("res://outils/bots/bots.gd")

const DT := 1.0 / 60.0
const SEC := 60 # pas par seconde
const MIN_TELEGRAPH := 0.4 # s : un coup doit être précédé d'un télégraphe rouge au moins aussi long
const TELEGRAPH_LOOKBACK := 4 # s : fenêtre où chercher ce télégraphe avant le coup
const FLOOR_SEEDS := 60 # valeur web : 60
const SECTION_LAST_COMBAT := 17
const NEW_KINDS := ["pavois", "stalker", "banner"]
const ENTRY := {"pavois": [10.0, 12.0], "stalker": [12.0, 14.0], "banner": [14.0, 16.0]} # étage de première apparition attendu
const BIG_HP := 5000.0
const HIGH_FLOOR := 600.0
const GEOM_EPS := 0.5
const APPROACH_STOP := 36.0 # u entre les centres : au contact
const ANGLE_EPS := 1e-9
const ROOM_END_SEEDS := 6 # valeur web : 6 (graines 1 à 6 du test « la salle se termine toujours »)
const ROOM_END_MAX_SECONDS := 180

# ---------------------------------------------------------------- outillage

## Salle vidée et « hors combat », héros immobile au centre bas. Les ennemis sont posés à la main.
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

static func _has_event(evs: Array, type: String) -> bool:
	return evs.any(func(ev): return ev.type == type)

static func _count_events(evs: Array, type: String) -> int:
	return evs.filter(func(ev): return ev.type == type).size()

static func _is_guard_deflect(ev: Dictionary) -> bool:
	return ev.type == "deflect" and D6Js.truthy(ev.get("guard"))

static func _stalker_hazard(game: Dictionary):
	for hz in game.hazards:
		if hz.get("kind") == "stalker":
			return hz
	return null

## a === b entre deux objets (ou null).
static func _same(a, b) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return is_same(a, b)

static func _kill_or_stun(game: Dictionary, e: Dictionary, how: String, stun: float) -> void:
	if how == "kill":
		D6Combat.kill_enemy(game, e, {"kind": "melee"})
	else:
		D6Combat.damage_enemy(game, e, {"kind": "wall", "amount": 1.0, "stun": stun, "canCrit": false})

## Le héros marche vers l'ennemi le plus proche jusqu'à `stop_at` u, sans frapper.
static func _approach_input(game: Dictionary, stop_at: float) -> Dictionary:
	var p: Dictionary = game.player
	var input: Dictionary = D6Game.empty_input()
	var best = null
	for e in game.enemies:
		if not e.dead and not (e.spawnT > 0.0) and (best == null or _dist(p, e) < _dist(p, best)):
			best = e
	if best != null and _dist(p, best) > stop_at:
		var d := _dist(p, best)
		input.moveX = (best.x - p.x) / d
		input.moveY = (best.y - p.y) / d
	return input

## Un télégraphe ROUGE (qui fait mal) est-il visible à l'écran ?
static func _red_telegraph_visible(game: Dictionary) -> bool:
	for e in game.enemies:
		if not e.dead and e.get("tele") != null and not D6Js.truthy(e.tele.get("harmless")):
			return true
	for hz in game.hazards:
		if not D6Js.truthy(hz.get("done")) and D6Js.truthy(hz.get("hitsPlayer")) and not D6Js.truthy(hz.get("burning")):
			return true
	return false

## Un coup d'arme porté à `e` depuis l'angle `from` (rad, autour de lui) : la direction va vers lui.
static func _strike_from(game: Dictionary, e: Dictionary, from: float, kind: String = "melee", extra: Dictionary = {}) -> float:
	var src := {"kind": kind, "amount": 10.0, "dirX": -D6Trig.cos(from), "dirY": -D6Trig.sin(from), "canCrit": false}
	src.merge(extra, true)
	return D6Combat.damage_enemy(game, e, src)

## Porte-pavois figé (ni pivot, ni coup), face tournée vers `face` : pour mesurer la seule garde.
static func _frozen_pavois(h, face: float) -> Dictionary:
	var g := _quiet_game({"godMode": true, "tuning": {"enemies": {"pavois": {"turnRate": 0.0, "attackRange": -1000.0, "speed": 0.0}}}})
	var e := _spawn_foe(g, "pavois", 0.0, -200.0)
	e.face = face
	_step(g)
	h.egal(e.face, face, "témoin : le pavois figé ne pivote pas")
	return {"g": g, "e": e}

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

static func _roster() -> Dictionary:
	var roster := {}
	for r in D6Data.tables().foe_data.EXTRA_ROSTER:
		roster[r.kind] = r
	return roster

static func _t_bestiaire(h) -> void:
	var first := _first_floors()
	var roster := _roster()
	for kind in NEW_KINDS:
		h.ok(roster.has(kind), "%s : pas dans EXTRA_ROSTER" % kind)
		var f: float = first.get(kind, INF)
		h.ok(is_finite(f), "%s : jamais tiré dans la 1re section" % kind)
		h.ok(f >= roster[kind].minIndex, "%s apparaît à l'étage %s, avant son minIndex %s" % [kind, f, roster[kind].minIndex])
		var lo: float = ENTRY[kind][0]
		var hi: float = ENTRY[kind][1]
		h.ok(f >= lo and f <= hi, "%s introduit à l'étage %s (attendu %s-%s)" % [kind, f, lo, hi])
	# Entrée progressive, APRÈS les archétypes existants (le dernier : le Nécromancien).
	var older: Array = D6Data.tables().foe_data.EXTRA_ROSTER.filter(func(r): return not NEW_KINDS.has(r.kind)).map(func(r): return r.minIndex)
	var entries: Array = NEW_KINDS.map(func(k): return roster[k].minIndex)
	h.ok(entries.min() > older.max(), "les nouveaux entrent après les anciens")
	var distinct := {}
	for x in entries:
		distinct[x] = true
	h.egal(distinct.size(), entries.size(), "un seul nouvel archétype par étage d'entrée")
	var sec2 := {}
	for seed in range(1, FLOOR_SEEDS + 1):
		for w in D6Game.create_game({"seed": float(seed), "startFloor": 19.0}).room.waves:
			for s in w:
				sec2[s.kind] = true
	for kind in NEW_KINDS:
		h.ok(sec2.has(kind), "section 2, étage 1 : %s absent (%s)" % [kind, ", ".join(sec2.keys())])

static func _t_dessin_donnees(h) -> void:
	var g: Dictionary = D6Game.create_game()
	for kind in NEW_KINDS:
		h.ok(D6Data.tables().foe_data.EXTRA_ENEMIES.get(kind), "pas de données pour %s" % kind)
		var def: Dictionary = g.tuning.enemies[kind]
		h.ok(D6Js.truthy(def.get("name")) and def.radius > 0.0 and def.hp > 0.0 and def.speed > 0.0 and def.mass > 0.0, "%s : données incomplètes" % kind)
		h.ok(def.gold is Array and def.gold[0] <= def.gold[1], "%s : or" % kind)
	h.non_portable("FOE_ART et FOE_BODY viennent de src/render (dessin web) : silhouettes et couleurs de corps non portées ; nom, données et or le sont")

# ---------------------------------------------------------------- lisibilité commune

static func _telegraph_case(h, kind: String) -> void:
	var g := _quiet_game({"bigHp": true})
	_spawn_foe(g, kind, 4.0, -4.0)
	var visible: Array = []
	var hurts := 0
	for i in 12 * SEC:
		visible.append(_red_telegraph_visible(g))
		for ev in _step(g, _approach_input(g, APPROACH_STOP) if kind == "pavois" else D6Game.empty_input()):
			if ev.type != "playerHurt":
				continue
			hurts += 1
			h.egal(ev.get("source"), kind, "%s : la cause du coup porte son nom" % kind)
			var best := _longest_run(visible)
			h.ok(best * DT >= MIN_TELEGRAPH, "%s : coup sans télégraphe rouge d'au moins %s s (vu %.2f s)" % [kind, MIN_TELEGRAPH, best * DT])
	if kind == "banner":
		h.egal(hurts, 0, "le porte-étendard ne frappe jamais")
	else:
		h.ok(hurts > 0, "%s : témoin — il doit avoir frappé un héros immobile en 12 s" % kind)

static func _t_lisibilite(h) -> void:
	for kind in NEW_KINDS:
		_telegraph_case(h, kind)

static func _measure(h, floor_num: float, elite) -> Dictionary:
	var g := _quiet_game({"startFloor": floor_num, "bigHp": true})
	var pav := _spawn_foe(g, "pavois", 0.0, -60.0, {"elite": elite})
	var c := {"tele": 0}
	var r := _step_until(g, func():
		if pav.get("tele") != null:
			c.tele += 1
		return pav.state == "recover", 10 * SEC)
	h.ok(r.ok, "étage %s : le porte-pavois doit frapper" % floor_num)
	var g2 := _quiet_game({"startFloor": floor_num, "bigHp": true})
	_spawn_foe(g2, "stalker", 0.0, -200.0, {"elite": elite})
	var r2 := _step_until(g2, func(): return _stalker_hazard(g2) != null, 10 * SEC)
	h.ok(r2.ok, "étage %s : le traqueur doit armer sa frappe" % floor_num)
	var hz = _stalker_hazard(g2)
	return {"pavois": c.tele, "stalker": hz.delay if hz != null else -1.0}

static func _t_telegraphes(h) -> void:
	var base := _measure(h, 1.0, null)
	h.ok(base.pavois * DT >= MIN_TELEGRAPH, "coup de pavois télégraphié %.2f s" % (base.pavois * DT))
	h.ok(base.stalker >= MIN_TELEGRAPH, "frappe du traqueur télégraphiée %s s" % base.stalker)
	h.egal(_measure(h, HIGH_FLOOR, null), base, "la profondeur ne raccourcit aucun télégraphe")
	h.egal(_measure(h, 1.0, "rapide"), base, "un champion rapide court plus vite, il ne frappe pas plus tôt")

# ---------------------------------------------------------------- Porte-pavois (garde de face)

static func _t_pavois_face(h) -> void:
	var fp := _frozen_pavois(h, 0.4)
	var g: Dictionary = fp.g
	var e: Dictionary = fp.e
	var def: Dictionary = g.tuning.enemies.pavois
	var half: float = def.guardArc / 2.0
	h.ok(D6FoeDefense.guard_up(g, e))
	for off in [0.0, half * 0.5, -half * 0.5, half - 0.02, -(half - 0.02)]:
		var hp: float = e.hp
		g.events.clear()
		var dealt := _strike_from(g, e, e.face + off, "melee", {"knockback": 400.0, "stun": 1.0})
		h.egal(dealt, 0.0, "de face (écart %.2f rad) : le coup ne porte pas" % off)
		h.egal(e.hp, hp)
		h.ok(e.kvx == 0.0 and e.kvy == 0.0, "aucun recul")
		h.ok(not (e.stun > 0.0), "aucun étourdissement")
		h.ok(g.events.any(_is_guard_deflect), "le coup arrêté se VOIT et s'ENTEND (événement de parade)")
		h.ok(not _has_event(g.events, "hit"), "pas d'événement de coup porté")
	for off in [PI, PI / 2.0, -PI / 2.0, half + 0.02, -(half + 0.02)]:
		var hp: float = e.hp
		var dealt := _strike_from(g, e, e.face + off)
		h.ok(dealt > 0.0, "de dos ou de flanc (écart %.2f rad) : le coup porte" % off)
		h.egal(e.hp, hp - dealt)

static func _t_pavois_sources(h) -> void:
	var fp := _frozen_pavois(h, -1.1)
	var g: Dictionary = fp.g
	var e: Dictionary = fp.e
	var def: Dictionary = g.tuning.enemies.pavois
	for kind in def.guardSources:
		h.egal(_strike_from(g, e, e.face, kind), 0.0, "%s de face" % kind)
	var sources: Array = def.guardSources.duplicate()
	sources.sort()
	h.egal(sources, ["melee", "skill", "strike"], "sources arrêtées")
	for kind in ["gadget", "super", "blast", "wall"]:
		h.ok(_strike_from(g, e, e.face, kind) > 0.0, "%s de face doit porter" % kind)
	# Coups sans direction (brûlure, éclair) : ils ne viennent d'aucun côté.
	h.ok(D6Combat.damage_enemy(g, e, {"kind": "burn", "amount": 5.0, "canCrit": false}) > 0.0)
	h.ok(D6Combat.damage_enemy(g, e, {"kind": "chain", "amount": 5.0, "canCrit": false}) > 0.0)

static func _t_pavois_baisse(h) -> void:
	var fp := _frozen_pavois(h, 0.0)
	var g: Dictionary = fp.g
	var e: Dictionary = fp.e
	h.egal(_strike_from(g, e, e.face), 0.0)
	D6Combat.damage_enemy(g, e, {"kind": "gadget", "amount": 1.0, "stun": 1.0, "canCrit": false})
	h.ok(e.stun > 0.0 and not D6FoeDefense.guard_up(g, e))
	h.ok(_strike_from(g, e, e.face) > 0.0, "étourdi : le coup de face porte")
	# Récupération : en vraie partie, après son coup.
	var g2 := _quiet_game({"bigHp": true})
	var pav := _spawn_foe(g2, "pavois", 0.0, -60.0)
	h.ok(_step_until(g2, func(): return pav.state == "windup", 6 * SEC).ok, "il arme son coup")
	h.ok(D6FoeDefense.guard_up(g2, pav), "pavois levé pendant le télégraphe")
	h.egal(_strike_from(g2, pav, pav.face), 0.0, "de face pendant le télégraphe : arrêté")
	h.ok(_step_until(g2, func(): return pav.state == "recover", 2 * SEC).ok)
	h.ok(not D6FoeDefense.guard_up(g2, pav))
	h.ok(_strike_from(g2, pav, pav.face) > 0.0, "pendant sa récupération : le coup de face porte")
	h.ok(_step_until(g2, func(): return pav.state == "chase", 3 * SEC).ok)
	h.egal(_strike_from(g2, pav, pav.face), 0.0, "garde relevée après la récupération")

## Le héros tient l'attaque vers `e` pendant `seconds` ; rend le nombre de coups arrêtés par la garde.
static func _attack_pavois(g: Dictionary, e: Dictionary, seconds: float) -> int:
	var p: Dictionary = g.player
	var deflects := 0
	for i in _iter(seconds * SEC):
		var input: Dictionary = D6Game.empty_input()
		input.attack = true
		input.aimX = e.x - p.x
		input.aimY = e.y - p.y
		for ev in _step(g, input):
			if _is_guard_deflect(ev):
				deflects += 1
	return deflects

static func _t_pavois_combo(h) -> void:
	var fp := _frozen_pavois(h, PI / 2.0) # pavois tourné vers le bas (vers le héros)
	var g: Dictionary = fp.g
	var e: Dictionary = fp.e
	var p: Dictionary = g.player
	p.x = e.x
	p.y = e.y + e.r + p.r + 12.0 # devant lui
	var hp: float = e.hp
	h.ok(_attack_pavois(g, e, 1.5) >= 2, "témoin : les coups de face sonnent sur le pavois")
	h.egal(e.hp, hp, "de face : aucun dégât")
	p.x = e.x
	p.y = e.y - e.r - p.r - 12.0 # dans son dos
	_attack_pavois(g, e, 1.5)
	h.ok(e.hp < hp, "de dos : il est blessé")

static func _t_pavois_pivot(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.pavois
	var e := _spawn_foe(g, "pavois", 0.0, -60.0)
	var p: Dictionary = g.player
	_step(g)
	var prev: float = e.face
	# Le héros saute de l'autre côté : il doit se retourner, jamais plus vite que turnRate.
	p.y = e.y - 60.0
	var turned := 0.0
	for i in _iter(0.5 * SEC):
		_step(g)
		var d := absf(D6Geo.angle_diff(prev, e.face))
		h.ok(d <= def.turnRate * DT + ANGLE_EPS, "pivot de %.4f rad en une image" % d)
		turned += d
		prev = e.face
	h.ok(turned > 0.5, "témoin : il se retourne vers le héros")
	h.ok(_step_until(g, func(): return e.state == "windup", 8 * SEC).ok, "il finit par armer son coup")
	var locked: float = e.face
	p.y = e.y + 60.0 # le héros repasse derrière pendant le télégraphe
	var r := _step_until(g, func():
		h.egal(e.face, locked, "face verrouillée (état %s)" % e.state)
		return e.state == "chase", 4 * SEC)
	h.ok(r.ok)
	h.ok(not _has_event(r.events, "playerHurt"), "passé dans son dos pendant le télégraphe : le coup de pavois manque")

static func _blocked_from_hero(g: Dictionary, e: Dictionary) -> bool:
	var p: Dictionary = g.player
	return D6FoeDefense.front_blocked(g, e, {"kind": "melee", "dirX": e.x - p.x, "dirY": e.y - p.y})

static func _t_pavois_dash(h) -> void:
	var g := _quiet_game({"godMode": true})
	var def: Dictionary = g.tuning.enemies.pavois
	var e := _spawn_foe(g, "pavois", 0.0, -70.0)
	e.cooldown = 99.0 # il ne frappe pas : on mesure le seul pivot
	var p: Dictionary = g.player
	for i in 10:
		_step(g)
	h.ok(_blocked_from_hero(g, e), "témoin : face à lui, les coups du héros rebondissent")
	var dash: Dictionary = D6Game.empty_input()
	dash.moveX = (e.x - p.x) / _dist(e, p)
	dash.moveY = (e.y - p.y) / _dist(e, p)
	dash.dashPressed = true
	_step(g, dash)
	h.ok(_step_until(g, func(): return p.state != "dash", SEC).ok)
	h.ok(not _blocked_from_hero(g, e), "après le dash : le héros est hors de la garde")
	var open := 0
	while not _blocked_from_hero(g, e) and open < 5 * SEC:
		_step(g)
		open += 1
	# Demi-tour à faire avant de couvrir de nouveau le héros : (PI - demi-garde) / turnRate, à peu près.
	var expected: float = (PI - def.guardArc / 2.0) / def.turnRate
	h.ok(open * DT >= 0.5, "fenêtre de %.2f s : trop courte pour placer un coup" % (open * DT))
	h.ok(absf(open * DT - expected) < 0.5, "fenêtre de %.2f s (attendu ~%.2f s)" % [open * DT, expected])

static func _pavois_cancel_case(h, how: String) -> void:
	var g2 := _quiet_game({"bigHp": true})
	var e2 := _spawn_foe(g2, "pavois", 0.0, -60.0)
	h.ok(_step_until(g2, func(): return e2.state == "windup" and e2.stateTime > 0.2, 6 * SEC).ok)
	_kill_or_stun(g2, e2, how, 1.2)
	var hp: float = g2.player.hp
	for i in _iter(1.2 * SEC):
		_step(g2)
		h.ok(e2.get("tele") == null, "%s : le télégraphe disparaît" % how)
	h.egal(g2.player.hp, hp, "%s : le coup est annulé" % how)

static func _t_pavois_coup(h) -> void:
	# Touché dans le secteur.
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, "pavois", 0.0, -60.0)
	h.ok(_step_until(g, func(): return e.state == "windup" and e.get("tele") != null, 6 * SEC).ok)
	var tele: Dictionary = D6Js.nz(e.get("tele"), {})
	h.ok(tele.get("shape") == "cone" and tele.get("area") == true and not D6Js.truthy(tele.get("harmless")), "télégraphe rouge en secteur")
	h.egal(tele.get("angle"), e.face, "le secteur est dessiné là où regarde le pavois")
	var r := _step_until(g, func(): return e.state == "recover", 2 * SEC)
	h.egal(_count_events(r.events, "playerHurt"), 1, "héros immobile dans le secteur : touché une fois")
	h.ok(r.events.any(func(ev): return ev.type == "enemyAttack" and ev.get("enemy") == "pavois"), "cri d'attaque")
	for how in ["kill", "stun"]:
		_pavois_cancel_case(h, how)

# ---------------------------------------------------------------- Traqueur (embuscade)

## Fait jouer un traqueur jusqu'à sa réapparition ; rend la partie, lui, et la zone de frappe.
static func _ambush(opts: Dictionary = {}) -> Dictionary:
	var o := {"bigHp": true}
	o.merge(opts, true)
	var g := _quiet_game(o)
	var e := _spawn_foe(g, "stalker", 0.0, -220.0, {"elite": opts.get("elite")})
	var seen := {"fade": 0, "hidden": 0}
	var r := _step_until(g, func():
		if e.state == "fade":
			seen.fade += 1
		if D6Js.truthy(e.get("hidden")):
			seen.hidden += 1
		return _stalker_hazard(g) != null, 10 * SEC)
	return {"g": g, "e": e, "seen": seen, "ok": r.ok, "events": r.events, "hazard": _stalker_hazard(g)}

static func _t_traqueur_embuscade(h) -> void:
	var a := _ambush()
	var g: Dictionary = a.g
	var e: Dictionary = a.e
	var def: Dictionary = g.tuning.enemies.stalker
	var p: Dictionary = g.player
	h.ok(a.ok, "il doit tendre son embuscade")
	h.ok(a.seen.fade * DT >= def.fade - 2.0 * DT, "dissolution visible %.2f s" % (a.seen.fade * DT))
	h.ok(a.seen.hidden * DT >= def.hiddenTime - 2.0 * DT, "disparu %.2f s" % (a.seen.hidden * DT))
	h.ok(not _has_event(a.events, "playerHurt"), "aucun dégât avant la frappe")
	h.ok(not D6Js.truthy(e.get("hidden")) and e.state == "windup", "réapparu, il arme sa frappe")
	h.ok(a.events.any(func(ev): return ev.type == "enemyAttack" and ev.get("enemy") == "stalker"), "cri à la réapparition : on entend le traqueur resurgir")
	# Dans le dos : à backDist, à l'opposé de l'orientation du héros.
	h.ok(absf(_dist(e, p) - def.backDist) < 1.0, "à %.1f u du héros" % _dist(e, p))
	var behind := D6Trig.atan2(e.y - p.y, e.x - p.x)
	h.ok(absf(D6Geo.angle_diff(p.facing + PI, behind)) < 0.01, "derrière le héros")
	_check_slash(h, a, def)

# La frappe : zone rouge autour de lui, liée à lui, télégraphiée ; puis l'impact et la récupération.
static func _check_slash(h, a: Dictionary, def: Dictionary) -> void:
	var g: Dictionary = a.g
	var e: Dictionary = a.e
	var hazard: Dictionary = D6Js.nz(a.hazard, {})
	h.ok(D6Js.truthy(hazard.get("hitsPlayer")) and not D6Js.truthy(hazard.get("hitsEnemies")) and hazard.get("sourceId") == e.id)
	h.ok(_num(hazard, "delay") >= MIN_TELEGRAPH and _num(hazard, "delay") >= def.slashWindup)
	h.ok(_hypot(_num(hazard, "x") - e.x, _num(hazard, "y") - e.y) < 1.0 and hazard.get("r") == def.slashRadius)
	var r := _step_until(g, func(): return e.state == "recover", 2 * SEC)
	var hurts: Array = r.events.filter(func(ev): return ev.type == "playerHurt")
	h.egal(hurts.size(), 1, "héros immobile : touché une fois")
	if hurts.size() > 0:
		h.egal(hurts[0].get("source"), "stalker")
	# Longue récupération : il reste là, visible et vulnérable.
	h.ok(D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 1.0, "canCrit": false}) > 0.0, "vulnérable pendant sa récupération")

static func _t_traqueur_disparu(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, "stalker", 0.0, -220.0)
	h.ok(_step_until(g, func(): return e.state == "fade", 8 * SEC).ok)
	h.ok(D6Combat.damage_enemy(g, e, {"kind": "burn", "amount": 1.0, "canCrit": false}) > 0.0, "pendant la dissolution : vulnérable")
	h.ok(_step_until(g, func(): return e.get("hidden") == true, 2 * SEC).ok)
	h.ok(e.spawnT > 0.0, "disparu : hors du jeu comme une apparition en attente")
	var hp: float = e.hp
	for kind in ["melee", "skill", "gadget", "super", "burn"]:
		h.egal(D6Combat.damage_enemy(g, e, {"kind": kind, "amount": 50.0, "dirX": 1.0, "dirY": 0.0, "stun": 1.0, "canCrit": false}), 0.0, "%s sur un traqueur disparu" % kind)
	h.egal(e.hp, hp)
	h.ok(not (e.stun > 0.0))

static func _traqueur_cancel_case(h, how: String) -> void:
	# Pendant la dissolution : il ne disparaît pas, aucune zone ne naît.
	var g := _quiet_game({"bigHp": true})
	var e := _spawn_foe(g, "stalker", 0.0, -220.0)
	h.ok(_step_until(g, func(): return e.state == "fade", 8 * SEC).ok)
	var stun := 1.0
	_kill_or_stun(g, e, how, stun)
	for i in _iter(stun * SEC - 2.0):
		_step(g)
		h.ok(not D6Js.truthy(e.get("hidden")), "%s pendant la dissolution : il ne disparaît pas" % how)
		h.ok(_stalker_hazard(g) == null, "%s : aucune frappe" % how)
	# Pendant le télégraphe : la zone est annulée, visiblement.
	var a := _ambush()
	h.ok(a.ok)
	_kill_or_stun(a.g, a.e, how, stun)
	var hp: float = a.g.player.hp
	var cancels := 0
	for i in _iter(1.5 * SEC):
		for ev in _step(a.g):
			if ev.type == "hazardCancel":
				cancels += 1
	h.egal(a.g.player.hp, hp, "%s pendant le télégraphe : aucun dégât" % how)
	h.ok(cancels >= 1, "%s : annulation visible (hazardCancel)" % how)

static func _t_traqueur_annulation(h) -> void:
	for how in ["kill", "stun"]:
		_traqueur_cancel_case(h, how)

static func _t_traqueur_esquive(h) -> void:
	# À pied, droit devant (à l'opposé de lui).
	var a := _ambush()
	var p: Dictionary = a.g.player
	var ae: Dictionary = a.e
	var away: Dictionary = D6Game.empty_input()
	away.moveX = (p.x - ae.x) / _dist(p, ae)
	away.moveY = (p.y - ae.y) / _dist(p, ae)
	var r := _step_until(a.g, func(): return ae.state == "recover", 2 * SEC, away)
	h.ok(not _has_event(r.events, "playerHurt"), "sorti du cercle : pas touché")
	# Esquive parfaite : immobile, dash lancé juste avant l'impact.
	var b := _ambush()
	var bg: Dictionary = b.g
	var be: Dictionary = b.e
	var def: Dictionary = bg.tuning.enemies.stalker
	var wait := int(D6Js.jround((def.slashWindup - 0.08) * SEC))
	for i in wait:
		_step(bg)
	var dodges: float = bg.telemetry.dodges
	var dash: Dictionary = D6Game.empty_input()
	dash.moveX = 1.0
	dash.dashPressed = true
	var ev1 := _step(bg, dash)
	var r2 := _step_until(bg, func(): return be.state == "recover", 2 * SEC)
	h.ok(not _has_event(ev1 + r2.events, "playerHurt"), "dash au bon moment : pas touché")
	h.egal(bg.telemetry.dodges, dodges + 1.0, "la frappe traversée pendant le dash compte comme une esquive parfaite")

static func _t_traqueur_murs(h) -> void:
	var g := _quiet_game({"bigHp": true})
	var def: Dictionary = g.tuning.enemies.stalker
	var room: Dictionary = g.room
	room.obstacles = [{"x0": 300.0, "y0": 300.0, "x1": 420.0, "y1": 420.0}]
	var e := _spawn_foe(g, "stalker", 0.0, -220.0)
	var p: Dictionary = g.player
	var spots := [
		[room.pad + p.r + 1.0, room.h / 2.0, 0.0], # dos au mur gauche, tourné vers la droite
		[room.w - room.pad - p.r - 1.0, room.h / 2.0, PI], # dos au mur droit
		[room.w / 2.0, room.pad + p.r + 1.0, PI / 2.0], # dos au mur du haut
		[room.pad + p.r + 1.0, room.pad + p.r + 1.0, PI / 4.0], # dans un coin
		[440.0, 360.0, 0.0], # dos à un obstacle
	]
	for spot in spots:
		p.x = spot[0]
		p.y = spot[1]
		p.facing = spot[2]
		var pt: Dictionary = D6FoeStalker.ambush_point(g, e, def)
		h.ok(not D6Physics.point_blocked(room, pt.x, pt.y, e.r), "réapparition bloquée en (%.0f, %.0f) pour un héros en (%s, %s)" % [pt.x, pt.y, spot[0], spot[1]])
		h.ok(absf(_hypot(pt.x - spot[0], pt.y - spot[1]) - def.backDist) < 1.0 or (pt.x == e.x and pt.y == e.y), "à backDist du héros (ou sur place, faute de mieux)")

static func _t_traqueur_jeton(h) -> void:
	var g := _quiet_game({"godMode": true, "tuning": {"combat": {"maxAttackers": 1.0}, "enemies": {"stalker": {"cooldown": 0.5}}}})
	for i in 3:
		_spawn_foe(g, "stalker", -200.0 + i * 200.0, -220.0)
	var busy := ["fade", "ambush", "windup"]
	var ambushes := 0
	for i in 25 * SEC:
		for ev in _step(g):
			if ev.type == "enemyAttack":
				ambushes += 1
		var n: int = g.enemies.filter(func(e): return busy.has(e.state)).size()
		h.ok(n <= 1, "%d traqueurs en embuscade en même temps (plafond 1)" % n)
		h.egal(D6AiCommon.active_attackers(g), n, "le jeton est compté pendant toute l'embuscade")
	h.ok(ambushes >= 4, "témoin : ils se relaient (%d embuscades)" % ambushes)

# ---------------------------------------------------------------- Porte-étendard (soutien)

static func _hit20(g: Dictionary, e: Dictionary) -> float:
	return D6Combat.damage_enemy(g, e, {"kind": "wall", "amount": 20.0, "canCrit": false})

static func _t_etendard_aura(h) -> void:
	var g := _quiet_game({"godMode": true, "tuning": {"enemies": {"banner": {"speed": 0.0}, "brute": {"speed": 0.0}, "pavois": {"speed": 0.0, "turnRate": 0.0, "attackRange": -1000.0}}}})
	var def: Dictionary = g.tuning.enemies.banner
	var b := _spawn_foe(g, "banner", 0.0, -400.0)
	var near: Dictionary = D6Enemies.create_enemy(g, "brute", b.x + def.auraRadius - 30.0, b.y, {"spawnT": 0.0})
	var far: Dictionary = D6Enemies.create_enemy(g, "brute", b.x - def.auraRadius - 60.0, b.y, {"spawnT": 0.0})
	var other: Dictionary = D6Enemies.create_enemy(g, "banner", b.x, b.y + 80.0, {"spawnT": 0.0})
	_step(g)
	h.ok(_same(D6FoeDefense.ward_of(g, near), b))
	h.ok(D6FoeDefense.ward_of(g, far) == null)
	h.ok(D6FoeDefense.ward_of(g, b) == null)
	h.ok(D6FoeDefense.ward_of(g, other) == null, "deux étendards ne se protègent pas l'un l'autre")
	h.egal(_hit20(g, far), 20.0)
	h.egal(_hit20(g, b), 20.0)
	h.egal(_hit20(g, other), 20.0)
	h.egal(_hit20(g, near), D6Js.jround(20.0 * def.wardMult), "sous l'aura")
	h.ok(def.wardMult > 0.0 and def.wardMult < 1.0)
	h.egal(D6FoeDefense.ward_mult(g, near), def.wardMult)
	# L'aura se VOIT, et elle est inoffensive.
	var tele = b.get("tele")
	h.ok(tele != null and tele.get("harmless") == true and tele.get("r") == def.auraRadius, "aura dessinée en alerte inoffensive")

static func _etendard_case(h, how: String) -> void:
	var g := _quiet_game({"godMode": true, "tuning": {"enemies": {"banner": {"speed": 0.0}, "brute": {"speed": 0.0}}}})
	var b := _spawn_foe(g, "banner", 0.0, -400.0)
	var ally: Dictionary = D6Enemies.create_enemy(g, "brute", b.x + 100.0, b.y, {"spawnT": 0.0})
	_step(g)
	h.ok(_same(D6FoeDefense.ward_of(g, ally), b))
	_kill_or_stun(g, b, how, 1.0)
	h.ok(D6FoeDefense.ward_of(g, ally) == null, "%s : plus de protection" % how)
	h.egal(_hit20(g, ally), 20.0)
	_step(g)
	h.ok(b.get("tele") == null, "%s : l'aura n'est plus dessinée" % how)
	if how == "stun":
		h.ok(_step_until(g, func(): return not (b.stun > 0.0), 2 * SEC).ok)
		_step(g)
		h.ok(_same(D6FoeDefense.ward_of(g, ally), b), "relevé, il protège de nouveau")
		h.ok(b.get("tele") != null and D6Js.truthy(b.tele.get("harmless")))

static func _t_etendard_chute(h) -> void:
	for how in ["kill", "stun"]:
		_etendard_case(h, how)

static func _t_etendard_soutien(h) -> void:
	var g := _quiet_game({"bigHp": true, "tuning": {"enemies": {"brute": {"speed": 0.0, "attackRange": -1000.0}}}})
	var def: Dictionary = g.tuning.enemies.banner
	var p: Dictionary = g.player
	var ally := _spawn_foe(g, "brute", 40.0, 0.0) # au contact du héros
	var b := _spawn_foe(g, "banner", 0.0, -520.0)
	h.ok(D6FoeDefense.ward_of(g, ally) == null, "témoin : trop loin au départ")
	var r := _step_until(g, func(): return _same(D6FoeDefense.ward_of(g, ally), b), 10 * SEC)
	h.ok(r.ok, "il finit par couvrir l'ennemi qui serre le héros")
	for i in 6 * SEC:
		_step(g)
	h.ok(_same(D6FoeDefense.ward_of(g, ally), b), "et il le couvre toujours 6 s plus tard")
	h.egal(p.hp, BIG_HP, "aucun dégât : il ne frappe jamais")
	h.egal(def.damage, 0.0)
	# Serré de près, il recule (lentement : on le rattrape).
	var g2 := _quiet_game({"bigHp": true})
	var b2 := _spawn_foe(g2, "banner", 0.0, -60.0)
	var d0 := _dist(b2, g2.player)
	for i in SEC:
		_step(g2)
	h.ok(_dist(b2, g2.player) > d0 + 20.0, "il s'écarte du héros")
	h.ok(def.speed < g2.tuning.player.speed, "plus lent que le héros")

# ---------------------------------------------------------------- champions

static func _draw(g: Dictionary, kind: String) -> Dictionary:
	var s := {}
	for i in 600:
		s[D6FoeElites.pick_elite_mod(g, kind, {"section": 3.0, "indexInSection": 10.0})] = true
	return s

## Champions planifiés dans les salles d'élite : {kind: {mod: true}}.
static func _elite_rooms(h) -> Dictionary:
	var roster := _roster()
	var seen := {}
	for seed in range(1, FLOOR_SEEDS + 1):
		for fl in [6.0, 11.0, 13.0, 15.0, 25.0]:
			var g: Dictionary = D6Game.create_game({"seed": float(seed), "startFloor": fl})
			D6Run.enter_floor(g, fl, {"reward": "elite"})
			if g.room.kind != "elite":
				continue
			for w in g.room.waves:
				for s in w:
					if not D6Js.truthy(s.get("elite")):
						continue
					h.different(s.kind, "banner")
					if NEW_KINDS.has(s.kind):
						h.ok(fl >= roster[s.kind].minIndex, "champion %s à l'étage %s, avant son entrée" % [s.kind, fl])
					if not seen.has(s.kind):
						seen[s.kind] = {}
					seen[s.kind][s.elite] = true
	return seen

static func _t_champions(h) -> void:
	var elite_kinds: Array = D6Data.tables().foe_data.EXTRA_ELITE_KINDS
	h.ok(elite_kinds.has("pavois") and elite_kinds.has("stalker"))
	h.ok(not elite_kinds.has("banner"))
	var g: Dictionary = D6Game.create_game({"seed": 9.0})
	var pav := _draw(g, "pavois")
	var sta := _draw(g, "stalker")
	h.ok(not pav.has("bouclier") and not pav.has("blinde"), "pavois : %s" % ", ".join(pav.keys()))
	h.ok(not sta.has("bouclier") and not sta.has("invocateur"), "traqueur : %s" % ", ".join(sta.keys()))
	h.ok(pav.size() >= 3 and sta.size() >= 3, "il leur reste au moins trois modificateurs")
	# En vrai : ils sortent champions des salles d'élite, jamais avant leur étage d'entrée.
	var seen := _elite_rooms(h)
	var sp: Dictionary = seen.get("pavois", {})
	var ss: Dictionary = seen.get("stalker", {})
	h.ok(sp.size() > 0 and ss.size() > 0, "champions planifiés : %s" % ", ".join(seen.keys()))
	h.ok(not sp.has("bouclier") and not sp.has("blinde") and not ss.has("bouclier") and not ss.has("invocateur"))
	# Un champion traqueur frappe plus large (comme la Brute), jamais plus tôt.
	var a := _ambush({"elite": "ardent"})
	var def: Dictionary = a.g.tuning.enemies.stalker
	h.ok(a.ok)
	var hazard: Dictionary = D6Js.nz(a.hazard, {})
	h.egal(hazard.get("r"), def.slashRadius * a.g.tuning.elite.sizeMult)
	h.egal(hazard.get("delay"), def.slashWindup)

# ---------------------------------------------------------------- bots : ils lisent ce qui se voit

static func _duel(kind: String, policy: String, seconds: int, opts: Dictionary = {}) -> Dictionary:
	var g := _quiet_game({"seed": D6Js.nz(opts.get("seed"), 3.0), "bigHp": true})
	g.room.kind = "combat"
	var e := _spawn_foe(g, kind, 0.0, -260.0)
	var mem := {}
	var hurts := 0
	var deflects := 0
	var steps := 0
	while steps < seconds * SEC and not e.dead:
		for ev in _step(g, Bots.play(policy, g, mem)):
			if ev.type == "playerHurt":
				hurts += 1
			if _is_guard_deflect(ev):
				deflects += 1
		steps += 1
	return {"dead": e.dead, "hurts": hurts, "deflects": deflects, "time": steps * DT, "dashes": g.telemetry.dashes}

static func _t_bots_duels(h) -> void:
	for kind in NEW_KINDS:
		var sk := _duel(kind, "skilled", 30)
		h.ok(sk.dead, "skilled contre %s : pas tué en 30 s" % kind)
		var nd := _duel(kind, "noDash", 45)
		h.ok(nd.dead, "noDash contre %s : pas tué en 45 s" % kind)
		var ma := _duel(kind, "masher", 90)
		h.ok(ma.dead, "masher contre %s : pas tué en 90 s (la salle doit toujours pouvoir se finir)" % kind)

static func _t_bot_habile(h) -> void:
	var pav := _duel("pavois", "skilled", 30)
	var mash := _duel("pavois", "masher", 90)
	h.ok(pav.dead and mash.dead)
	h.ok(pav.deflects < mash.deflects, "le bot habile tape moins dans le pavois (%d) que celui qui martèle (%d)" % [pav.deflects, mash.deflects])
	h.ok(pav.hurts <= 1, "le bot habile lit le coup de pavois (%d coups reçus)" % pav.hurts)
	h.ok(mash.hurts > pav.hurts, "marteler de face se paie")
	# Traqueur : trois embuscades sans le tuer (héros qui ne frappe pas : on ne lit que l'esquive).
	var g := _quiet_game({"seed": 5.0, "bigHp": true, "tuning": {"enemies": {"stalker": {"hp": 1e6, "cooldown": 0.5}}}})
	g.room.kind = "combat"
	_spawn_foe(g, "stalker", 0.0, -260.0)
	var mem := {}
	var ambushes := 0
	var hurts := 0
	for i in 20 * SEC:
		for ev in _step(g, Bots.play("skilled", g, mem)):
			if ev.type == "enemyAttack":
				ambushes += 1
			if ev.type == "playerHurt":
				hurts += 1
	h.ok(ambushes >= 3, "témoin : %d embuscades" % ambushes)
	h.ok(hurts <= ambushes / 3.0, "le bot habile sort du cercle (%d coups pour %d embuscades)" % [hurts, ambushes])

# ---------------------------------------------------------------- parties réelles

## `check` : Callable(game) ou null.
static func _bot_run(seed: float, start_floor: float, steps: int, policy: String = "skilled", check = null) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed, "startFloor": start_floor})
	var mem := {}
	for i in steps:
		var k := 0
		while k < 8 and g.mode == "choice":
			Bots.resolve_choice(g, policy)
			k += 1
		if g.mode == "dead":
			D6Game.apply_command(g, {"type": "respawn"})
		if g.mode != "play":
			break
		D6Game.step_game(g, Bots.play(policy, g, mem))
		if check != null:
			check.call(g)
		g.events.clear()
	return g

static func _determinism_run(kinds: Dictionary) -> Array:
	var g := _bot_run(12.0, 14.0, 4000, "skilled", func(gg):
		for e in gg.enemies:
			kinds[e.kind] = true)
	var foes: Array = g.enemies.map(func(e): return [e.kind, e.state, e.get("face")])
	return [D6Game.state_hash(g), g.rng.gen.s, g.rng.combat.s, g.rng.ai.s, g.hazards.size(), g.spawns.size(), foes]

static func _t_determinisme(h) -> void:
	var kinds := {}
	h.egal(_determinism_run(kinds), _determinism_run(kinds))
	for kind in NEW_KINDS:
		h.ok(kinds.has(kind), "couverture : %s absent (%s)" % [kind, ", ".join(kinds.keys())])

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
	for ev in g.events:
		if _is_guard_deflect(ev):
			cover.deflects += 1
	for e in g.enemies:
		if e.dead:
			continue
		h.ok(e.hp > 0.0 and e.hp <= e.maxHp, "%s#%s vivant avec %s / %s" % [e.kind, e.id, e.hp, e.maxHp])
		var v := _geometry_violation(g.room, e.x, e.y, e.r)
		h.egal(v, "", "%s#%s %s (%.1f, %.1f)" % [e.kind, e.id, v, e.x, e.y])
		if cover.has(e.kind):
			cover[e.kind] += 1
		if D6Js.truthy(e.get("hidden")):
			cover.hidden += 1
			h.ok(e.kind == "stalker" and e.spawnT > 0.0 and e.get("tele") == null, "disparu : hors du jeu")
			h.ok(not g.hazards.any(func(hz): return hz.get("sourceId") == e.id and not D6Js.truthy(hz.get("done"))), "disparu : aucune zone à lui")
		if D6FoeDefense.ward_of(g, e) != null:
			cover.warded += 1

static func _t_invariants(h) -> void:
	var cover := {"pavois": 0, "stalker": 0, "banner": 0, "hidden": 0, "warded": 0, "deflects": 0}
	for run in [[2.0, "skilled"], [12.0, "skilled"], [12.0, "noDash"], [12.0, "masher"]]:
		_bot_run(run[0], 14.0, 4000, run[1], func(g): _invariant_check(h, g, cover))
	for k in cover.keys():
		h.ok(cover[k] > 0, "couverture : %s jamais vu (%s)" % [k, JSON.stringify(cover)])

## Joue le combat de la salle de départ ; rend la partie à la fin (salle nettoyée, héros mort, ou délai).
static func _play_room(policy: String, seed: float, floor_num: float, seen: Dictionary) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed, "startFloor": floor_num})
	var mem := {}
	var i := 0
	while i < ROOM_END_MAX_SECONDS * SEC and g.mode == "play" and not g.room.cleared:
		D6Game.step_game(g, Bots.play(policy, g, mem))
		for e in g.enemies:
			seen[e.kind] = true
		g.events.clear()
		i += 1
	return g

static func _t_salle_se_termine(h) -> void:
	var seen := {}
	for policy in ["skilled", "noDash"]:
		for seed in range(1, ROOM_END_SEEDS + 1):
			for fl in [10.0, 12.0, 14.0, 16.0]:
				var g := _play_room(policy, float(seed), fl, seen)
				var alive: Array = g.enemies.filter(func(e): return not e.dead).map(func(e): return e.kind)
				h.ok(g.room.cleared or g.mode != "play", "%s, graine %d, étage %s : salle toujours en cours après %d s (%s)" % [policy, seed, fl, ROOM_END_MAX_SECONDS, ", ".join(alive)])
	for kind in NEW_KINDS:
		h.ok(seen.has(kind), "couverture : %s jamais rencontré" % kind)

# ---------------------------------------------------------------- les tests

static func tests(h) -> void:
	h.test("bestiaire 2 : pavois, traqueur et étendard entrent un par un dans la 1re section, jamais avant leur étage ; tous là dès la section 2", func(): _t_bestiaire(h))
	h.test("dessin, noms et données : chaque nouvel archétype a sa silhouette, sa couleur, son nom, son or et son coût", func(): _t_dessin_donnees(h))
	h.test("chaque nouvel archétype, posé SUR le héros : tout dégât est précédé d'un télégraphe rouge visible — aucun dégât de contact", func(): _t_lisibilite(h))
	h.test("télégraphes : durées au-dessus du seuil, identiques à l'étage 1 et à l'étage 600, et pour un champion « rapide »", func(): _t_telegraphes(h))
	h.test("Porte-pavois : frappé de face il ne prend RIEN (ni dégât, ni recul, ni étourdissement) ; de dos et de flanc il prend tout", func(): _t_pavois_face(h))
	h.test("Porte-pavois : seuls l'arme et la compétence rebondissent ; gadget, Super, brûlure, éclair et mur passent même de face", func(): _t_pavois_sources(h))
	h.test("Porte-pavois : étourdi, ou pendant la récupération de son propre coup, le pavois est baissé — tout passe de face", func(): _t_pavois_baisse(h))
	h.test("Porte-pavois : en vraie partie, le combo de face ne lui fait rien ; le même combo dans son dos le blesse", func(): _t_pavois_combo(h))
	h.test("Porte-pavois : il pivote au plus à turnRate, sa face est VERROUILLÉE pendant le télégraphe et la récupération", func(): _t_pavois_pivot(h))
	h.test("Porte-pavois : un dash à travers lui dépose le héros dans son dos, hors de la garde, pour une vraie fenêtre de frappe", func(): _t_pavois_dash(h))
	h.test("Porte-pavois : le coup de pavois ne touche que dans le secteur dessiné ; l'étourdir ou le tuer pendant le télégraphe l'annule", func(): _t_pavois_coup(h))
	h.test("Traqueur : il se dissout (visible, vulnérable), disparaît (intouchable), resurgit DANS LE DOS du héros, puis frappe après un télégraphe rouge", func(): _t_traqueur_embuscade(h))
	h.test("Traqueur : disparu, il n'est ni touchable ni ciblé ; dissous à moitié, il l'est encore", func(): _t_traqueur_disparu(h))
	h.test("Traqueur : le tuer ou l'étourdir pendant la dissolution annule l'embuscade ; pendant le télégraphe, annule la frappe", func(): _t_traqueur_annulation(h))
	h.test("Traqueur : sortir du cercle (à pied ou d'un dash) évite la frappe ; dasher À TRAVERS au bon moment est une esquive parfaite", func(): _t_traqueur_esquive(h))
	h.test("Traqueur : il ne resurgit jamais dans un mur ni dans un obstacle, même quand le héros est dos au mur", func(): _t_traqueur_murs(h))
	h.test("Traqueur : il garde son jeton de mêlée de la dissolution à la frappe — jamais plus d'attaquants que le plafond", func(): _t_traqueur_jeton(h))
	h.test("Porte-étendard : sous son aura les AUTRES prennent wardMult des dégâts ; hors de l'aura, lui-même et un autre étendard prennent tout", func(): _t_etendard_aura(h))
	h.test("Porte-étendard : l'étourdir fait tomber l'aura (et son dessin) ; le tuer aussi — la protection cesse aussitôt", func(): _t_etendard_chute(h))
	h.test("Porte-étendard : il n'attaque jamais, vient couvrir la mêlée d'un héros immobile, et recule quand on le serre", func(): _t_etendard_soutien(h))
	h.test("champions : pavois et traqueur peuvent l'être (exclusions tenues) ; le porte-étendard jamais", func(): _t_champions(h))
	h.test("bots : seul face à chaque nouvel archétype, le bot habile le tue vite ; sans dash aussi ; celui qui martèle finit par l'avoir", func(): _t_bots_duels(h))
	h.test("bot habile : il contourne le pavois au lieu de taper dedans, et sort du cercle du traqueur", func(): _t_bot_habile(h))
	h.test("déterminisme : mêmes graine et entrées => même partie, les trois nouveaux archétypes en jeu", func(): _t_determinisme(h))
	h.test("invariants en partie réelle (bots habile et sans dash, étages 14+) : PV bornés, personne dans un mur, un traqueur disparu n'attaque pas", func(): _t_invariants(h))
	h.test("la salle se termine toujours : aux étages où ils apparaissent, chaque combat joué par un bot finit (salle nettoyée ou héros mort)", func(): _t_salle_se_termine(h))
	h.test("audio : cris d'attaque du pavois et du traqueur, coup arrêté par le pavois, frappe du traqueur — sans erreur WebAudio", func():
		h.non_portable("teste src/audio/sfx.mjs (WebAudio simulé) : pas d'audio web sous Godot"))
