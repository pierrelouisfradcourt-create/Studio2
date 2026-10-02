extends RefCounted
## DÉFAUTS DE RÈGLES, troisième lot (2026-10-02) : le reste du tableau d'origine (DEFAUTS.md).
## Points corrigés (1, 2, 5) : un test rouge sur le code d'avant, vert après. Points jugés « pas un
## défaut » (3, 4) : un test TÉMOIN, vert avant comme après, qui fixe ce qui a été jugé.

const MAX_DRAWS := 64 # tirages cherchés au plus entre deux états d'un générateur
const NO_ROOM := 5000.0 # u : anneau d'apparition hors de toute salle (aucun point possible)
const CALL_TIMEOUT := 3.0 # s : appel des geôliers (télégraphe : 0,9 s)
const FLUSH := 1.0 # u : en deçà, un obstacle est « collé » au mur (ROOM_SLACK de donnees.gd)
const SETTLE_STEPS := 30 # images laissées à un corps pour sortir d'un obstacle
const TOUCH := 1e-6 # u : tolérance d'un contact
const SIGHT_CUT := 8.0 # u : côté du coin de pilier coupé par un regard (corde de 11 u, sous les 16 u d'un échantillon)
const SIGHT_RUN := 80.0 # u : longueur d'un regard de part et d'autre du coin, répartie de 81 façons
const SHOT_CUT := 0.6 # corde coupée dans le coin par un tir, en part de son pas (plus courte qu'un pas)
const SHOT_RUN := 60.0 # u parcourues avant le coin
const SHOT_PHASES := 12 # départs décalés d'un douzième de pas : toutes les façons de tomber autour du coin
const PLAY_STEPS := 240 # images jouées pour comparer deux parties
const SQRT2 := 1.4142135623730951

static func _layouts() -> Dictionary:
	var all: Dictionary = D6Data.tables().room.LAYOUTS.duplicate()
	all["BOSS_LAYOUT"] = D6Data.tables().room.BOSS_LAYOUT
	return all

## Pose dans la salle les obstacles d'une vraie disposition (data/salles.json), comme D6Room.build_room.
static func _lay(g: Dictionary, id: String) -> void:
	var room: Dictionary = g.room
	room.obstacles = []
	for rect in _layouts()[id]:
		var cx: float = rect[0] * room.w
		var cy: float = rect[1] * room.h
		room.obstacles.append({"x0": cx - rect[2] / 2.0, "y0": cy - rect[3] / 2.0, "x1": cx + rect[2] / 2.0, "y1": cy + rect[3] / 2.0})
	room.layout = id
	room.nav = D6Nav.build_nav(room)

# ---------------------------------------------------------------- 1. Minos : un tirage par brèche

## Tirages faits entre l'état `before` (copie) et l'état `now` d'un générateur ; -1 au-delà de MAX_DRAWS.
static func _draws(before: Dictionary, now: Dictionary) -> int:
	for n in MAX_DRAWS + 1:
		if before.s == now.s:
			return n
		D6Rng.rand(before)
	return -1

## Premier pas d'une sentence de Minos en phase `phase` : [tirages faits, tirages utiles].
static func _sentence_draws(h, phase: float) -> Array:
	var g: Dictionary = h.bac_a_sable({"seed": 21.0})
	var s: Dictionary = g.tuning.boss.minos.sentence
	var e: Dictionary = D6Enemies.create_enemy(g, "minos", g.room.w / 2.0, g.room.h * 0.3, {"boss": true, "spawnT": 0.0})
	e.phase = phase
	D6BossCommon.set_state(e, "sentence")
	var before: Dictionary = D6Rng.clone_rng(g.rng.ai)
	D6BossMinos.sentence(g, e, g.tuning.boss.minos, D6Data.DT)
	var bands: float = s.bandsH if e.sweepH else s.bandsV
	# L'orientation, le sens, puis UNE brèche commune (phase 1) ou une brèche par bande.
	return [_draws(before, g.rng.ai), int(2.0 + (1.0 if phase < s.ownBreachFromPhase else bands))]

static func _t_minos_tirage(h) -> void:
	var s: Dictionary = D6Data.default_tuning().boss.minos.sentence
	var one: Array = _sentence_draws(h, s.ownBreachFromPhase - 1.0)
	h.egal(one[0], one[1], "brèche commune (phase %s) : tirages du balayage" % D6Js.num_str(s.ownBreachFromPhase - 1.0))
	var own: Array = _sentence_draws(h, s.ownBreachFromPhase)
	h.egal(own[0], own[1], "une brèche par bande (phase %s) : aucun tirage pour une brèche commune qui ne sert pas" % D6Js.num_str(s.ownBreachFromPhase))

# ---------------------------------------------------------------- 2. Colosse : un appel sans geôlier ne compte pas

## Le Colosse appelle ses geôliers en phase 2 ; rend {g, e, events}.
static func _jailer_call(h, tuning) -> Dictionary:
	var g: Dictionary = h.bac_a_sable({"seed": 23.0, "tuning": tuning})
	var d: Dictionary = g.tuning.boss.colosse
	var e: Dictionary = D6Enemies.create_enemy(g, "colosse", g.room.w / 2.0, g.room.h * 0.35, {"boss": true, "spawnT": 0.0})
	e.phase = 2.0
	g.events.clear()
	D6BossCommon.set_state(e, "geoliers")
	for i in h.ticks(CALL_TIMEOUT):
		D6BossColosse.geoliers(g, e, d, D6Data.DT)
		if e.state == "rest":
			break
	return {"g": g, "e": e, "events": g.events.map(func(ev): return ev.type)}

static func _calls(e: Dictionary) -> float:
	var calls = e.get("jailerCalls")
	return 0.0 if calls == null else calls.get(D6Js.num_str(e.phase), 0.0)

static func _t_colosse_appel(h) -> void:
	# Témoin : dans la salle, l'appel fait venir les geôliers, lève le bouclier et compte.
	var ok: Dictionary = _jailer_call(h, null)
	var d: Dictionary = ok.g.tuning.boss.colosse
	h.egal(float(ok.g.spawns.size()), d.geoliers.countByPhase[1], "appel réussi : les geôliers arrivent")
	h.egal([_calls(ok.e), D6Js.truthy(ok.e.get("shielded"))], [1.0, true], "appel réussi : compté, bouclier levé")
	# Aucun point d'apparition (anneau hors de la salle) : personne ne vient.
	var none: Dictionary = _jailer_call(h, {"boss": {"colosse": {"geoliers": {"minR": NO_ROOM, "maxR": NO_ROOM}}}})
	h.egal(none.e.state, "rest", "l'appel se termine")
	h.egal(none.g.spawns.size(), 0, "aucun point d'apparition : aucun geôlier")
	h.egal(_calls(none.e), 0.0, "un appel sans geôlier ne consomme pas l'appel de la phase")
	h.egal(D6Js.truthy(none.e.get("shielded")), false, "ni ne lève un bouclier que personne ne tient")
	h.ok(not none.events.has("bossShield") and not none.events.has("bossSummon"), "ni bouclier ni invocation annoncés : %s" % str(none.events))
	h.egal(D6BossColosse._available(none.g, none.e, none.g.tuning.boss.colosse, "geoliers"), true, "il pourra rappeler ses geôliers dans cette phase")

# ---------------------------------------------------------------- 3. coffre plein (témoin)

static func _relic(name: String, score: float) -> Dictionary:
	return {"slot": "talisman", "rarity": "commun", "name": name, "level": 1.0, "affixes": [], "power": null, "base": {}, "score": score}

static func _full_stash(scores: Callable) -> Dictionary:
	var p: Dictionary = D6Profile.create_profile(D6Data.create_tuning())
	for i in int(D6Data.tables().profile.STASH_MAX):
		p.stash.append(_relic("a%d" % i, scores.call(i)))
	return p

static func _names(p: Dictionary) -> Array:
	return p.stash.map(func(it): return it.name)

static func _t_coffre_plein(h) -> void:
	var size: int = int(D6Data.tables().profile.STASH_MAX)
	# Scores égaux : le plus ancien part, l'objet qu'on vient de ranger reste.
	var even: Dictionary = _full_stash(func(_i): return 0.0)
	D6Profile.stash_loot(even, _relic("neuf", 0.0))
	h.egal(even.stash.size(), size, "le coffre reste plein, sans déborder")
	h.egal([_names(even).has("a0"), _names(even).has("a1"), _names(even)[-1]], [false, true, "neuf"], "à scores égaux, le plus ancien part")
	# Le moins bon part, où qu'il soit — sauf l'objet qu'on vient de ranger, même s'il est le pire.
	var mixed: Dictionary = _full_stash(func(i): return 1.0 if i == 7 else 5.0)
	D6Profile.stash_loot(mixed, _relic("pire", 0.0))
	h.egal([_names(mixed).has("a7"), _names(mixed).has("a0"), _names(mixed)[-1]], [false, true, "pire"], "le moins bon des anciens part ; jamais celui qu'on range")

# ---------------------------------------------------------------- 4. identifiants de départ (témoin)

static func _play(h, g: Dictionary) -> int:
	h.avancer(g, PLAY_STEPS, func(i): return {"moveX": 1.0 if i % 60 < 30 else -1.0, "moveY": -1.0, "attackPressed": i % 20 == 0, "attack": true})
	return D6Game.state_hash(g)

static func _t_identifiants(h) -> void:
	# Profil neuf : la partie crée l'équipement de départ. Profil déjà équipé : elle n'en a pas besoin.
	var fresh: Dictionary = D6Game.create_game({"seed": 5.0})
	var meta: Dictionary = D6Js.clone(fresh.meta)
	var kept: Dictionary = D6Game.create_game({"seed": 5.0, "meta": meta})
	h.egal(kept.run.items.arme.name, fresh.run.items.arme.name, "même équipement dans les deux parties")
	h.egal(kept.nextId, fresh.nextId, "les entités sont numérotées de la même façon, que le profil ait ou non son équipement")
	h.egal(kept.enemies.map(func(e): return e.id) + kept.spawns.map(func(s): return s.id), fresh.enemies.map(func(e): return e.id) + fresh.spawns.map(func(s): return s.id))
	h.egal(_play(h, kept), _play(h, fresh), "même graine, mêmes entrées : même partie (empreinte) avec un profil neuf ou repris")

# ---------------------------------------------------------------- 5a. obstacle collé au mur

## "" si le corps est dans la salle et hors de tout obstacle ; sinon, ce qui ne va pas.
static func _misplaced(room: Dictionary, ent: Dictionary) -> String:
	var lo: float = room.pad + ent.r - TOUCH
	if ent.x < lo or ent.y < lo or ent.x > room.w - lo or ent.y > room.h - lo:
		return "hors des murs (x = %s, y = %s, rayon %s)" % [str(ent.x), str(ent.y), str(ent.r)]
	for o in room.obstacles:
		var dx: float = ent.x - clampf(ent.x, o.x0, o.x1)
		var dy: float = ent.y - clampf(ent.y, o.y0, o.y1)
		if dx * dx + dy * dy < (ent.r - TOUCH) * (ent.r - TOUCH):
			return "dans un obstacle (x = %s, y = %s, rayon %s)" % [str(ent.x), str(ent.y), str(ent.r)]
	return ""

## Centres posés DANS chaque obstacle collé à un mur, contre ce mur : [{layout, x, y}] pour un rayon.
static func _flush_spots(room: Dictionary, id: String, r: float) -> Array:
	var out: Array = []
	for rect in _layouts()[id]:
		var cx: float = rect[0] * room.w
		var cy: float = rect[1] * room.h
		var w: float = rect[2]
		var hh: float = rect[3]
		if absf(cx - w / 2.0 - room.pad) <= FLUSH and w > r:
			out.append({"x": room.pad + r, "y": cy})
		if absf(cx + w / 2.0 - (room.w - room.pad)) <= FLUSH and w > r:
			out.append({"x": room.w - room.pad - r, "y": cy})
		if absf(cy - hh / 2.0 - room.pad) <= FLUSH and hh > r:
			out.append({"x": cx, "y": room.pad + r})
		if absf(cy + hh / 2.0 - (room.h - room.pad)) <= FLUSH and hh > r:
			out.append({"x": cx, "y": room.h - room.pad - r})
	return out

static func _t_obstacle_au_mur(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 25.0, "godMode": true})
	var t: Dictionary = g.tuning
	var cases := 0
	for id in _layouts():
		_lay(g, id)
		for r in [t.enemies.imp.radius, t.player.radius, t.enemies.charger.radius, t.enemies.brute.radius]:
			for spot in _flush_spots(g.room, id, r):
				cases += 1
				var ent := {"x": spot.x, "y": spot.y, "r": r}
				D6Physics.move_circle(g.room, ent, 0.0, 0.0)
				h.egal(_misplaced(g.room, ent), "", "disposition %s : un corps au centre pris dans l'obstacle collé au mur est rendu à la salle" % id)
	h.ok(cases >= 6, "les salles du jeu ont des obstacles collés au mur (%d cas essayés)" % cases)
	# Dans une vraie partie : un diablotin pris dans une alcôve en ressort DANS la salle, et y reste.
	_lay(g, "alcoves")
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h - g.room.pad - 80.0
	var spot: Dictionary = _flush_spots(g.room, "alcoves", t.enemies.imp.radius)[0]
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", spot.x, spot.y, {"spawnT": 0.0})
	var worst := ""
	for i in SETTLE_STEPS:
		D6Game.step_game(g, h.entree())
		g.events.clear()
		if worst == "":
			worst = _misplaced(g.room, e)
	h.egal(worst, "", "en partie, image après image")

# ---------------------------------------------------------------- 5b. le coin d'un pilier arrête regards et tirs

## Le coin bas-droit du premier pilier de la disposition « pillars ».
static func _corner(g: Dictionary) -> Dictionary:
	_lay(g, "pillars")
	var o: Dictionary = g.room.obstacles[0]
	return {"x": o.x1, "y": o.y1, "o": o}

static func _t_regard_coin(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 27.0})
	var c: Dictionary = _corner(g)
	var through := 0
	var beside := 0
	for a in range(0, int(SIGHT_RUN) + 1):
		var b: float = SIGHT_RUN - a
		# Diagonale qui coupe le coin sur SIGHT_CUT u de chaque côté : elle traverse le pilier.
		if D6Physics.line_of_sight(g.room, c.x + a, c.y - SIGHT_CUT - a, c.x - SIGHT_CUT - b, c.y + b):
			through += 1
		# La même, décalée hors du pilier (elle passe à 1 u du coin) : on voit.
		if D6Physics.line_of_sight(g.room, c.x + 1.0 + a, c.y + 1.0 - a, c.x + 1.0 - b, c.y + 1.0 + b):
			beside += 1
	h.egal(through, 0, "regards qui passent À TRAVERS le coin du pilier (sur %d)" % (int(SIGHT_RUN) + 1))
	h.egal(beside, int(SIGHT_RUN) + 1, "regards qui passent À CÔTÉ du coin : tous voient")
	h.egal(D6Physics.line_of_sight(g.room, c.o.x0 - 50.0, c.y, c.x + 50.0, c.y), true, "un regard qui rase le bord du pilier voit")
	h.egal(D6Physics.line_of_sight(g.room, c.o.x0 - 50.0, c.y - 10.0, c.x + 50.0, c.y - 10.0), false, "un regard à travers le pilier ne voit pas")

## Tirs lancés en diagonale à travers le coin du pilier, corde plus courte que leur pas, depuis
## SHOT_PHASES départs décalés : combien passent ? `fire.call(x, y, vx, vy)` rend le tir.
static func _shots_through(g: Dictionary, c: Dictionary, speed: float, fire: Callable, advance: Callable) -> int:
	var step: float = speed * D6Data.DT
	var cut: float = step * SHOT_CUT / SQRT2 # côté du coin coupé : corde = SHOT_CUT pas
	var passed := 0
	for k in SHOT_PHASES:
		var run: float = SHOT_RUN + step * k / SHOT_PHASES
		var shot: Dictionary = fire.call(c.x - cut / 2.0 + run / SQRT2, c.y - cut / 2.0 - run / SQRT2, -speed / SQRT2, speed / SQRT2)
		for i in int(ceilf((run + step * 2.0) / step)) + 1:
			advance.call()
		# Encore en vol une fois le coin dépassé : il est passé à travers.
		if not D6Js.truthy(shot.get("dead")):
			passed += 1
			shot.dead = true
	return passed

static func _t_tir_coin(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 29.0, "godMode": true})
	var c: Dictionary = _corner(g)
	var t: Dictionary = g.tuning
	var arrow: Dictionary = t.enemies.archer
	var lance: Dictionary = t.skills.lance
	var fastest := 0.0
	for w in t.weapons:
		for hit in t.weapons[w].combo:
			if hit.has("shot"):
				fastest = maxf(fastest, hit.shot.speed)
	var step_projectiles := func(): D6Projectiles.update_projectiles(g, D6Data.DT)
	var enemy_arrow := func(x, y, vx, vy): return D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": x, "y": y, "vx": vx, "vy": vy, "r": arrow.projRadius, "damage": arrow.damage, "range": arrow.projRange})
	h.egal(_shots_through(g, c, arrow.projSpeed, enemy_arrow, step_projectiles), 0, "flèches d'archer passées à travers le coin du pilier (sur %d)" % SHOT_PHASES)
	var hero_lance := func(x, y, vx, vy): return D6Projectiles.spawn_projectile(g, {"owner": "player", "kind": "lance", "x": x, "y": y, "vx": vx, "vy": vy, "r": lance.radius, "damage": lance.damage, "range": lance.range, "pierce": lance.pierce})
	h.egal(_shots_through(g, c, lance.speed, hero_lance, step_projectiles), 0, "Lances passées à travers le coin du pilier (sur %d)" % SHOT_PHASES)
	h.ok(fastest > 0.0, "une arme à distance existe")
	var hero_shot := func(x, y, vx, vy): return D6KitShots.spawn_shot(g, {"x": x, "y": y, "vx": vx, "vy": vy, "r": 5.0, "range": 2000.0, "damage": 1.0, "source": "melee"})
	h.egal(_shots_through(g, c, fastest, hero_shot, func(): D6KitShots.update_shots(g, D6Data.DT)), 0, "traits du héros (%s u/s) passés à travers le coin du pilier (sur %d)" % [D6Js.num_str(fastest), SHOT_PHASES])

static func tests(h) -> void:
	h.test("défaut 13 · Minos, sentence : un tirage par brèche, aucun pour une brèche commune qui ne sert pas", func(): _t_minos_tirage(h))
	h.test("défaut 14 · Colosse : un appel qui ne fait venir aucun geôlier ne consomme pas l'appel de la phase", func(): _t_colosse_appel(h))
	h.test("point 15 (témoin, pas un défaut) · coffre plein : le moins bon part, le plus ancien à égalité, jamais l'objet qu'on range", func(): _t_coffre_plein(h))
	h.test("point 16 (témoin, pas un défaut) · même numérotation des entités, que le profil ait ou non son équipement de départ", func(): _t_identifiants(h))
	h.test("défaut 17 · un corps pris dans un obstacle collé au mur ressort dans la salle, jamais dans le mur", func(): _t_obstacle_au_mur(h))
	h.test("défaut 18 · aucun regard ne traverse le coin d'un pilier", func(): _t_regard_coin(h))
	h.test("défaut 18 · aucun tir ne traverse le coin d'un pilier (flèche, Lance, trait du héros)", func(): _t_tir_coin(h))
