extends RefCounted
## COMPÉTENCES NEUVES DU REVENANT (combat V3, étape 4) — chargé par sim/kit_neuves.gd, sans class_name.
## Nombres : data/classes.json (`sillage`, `sceau`, `riposte`), rangs et améliorations : data/arbres.json.
##
##   sillage — Sillage de braise (à charges) : pendant `duration` s, le héros sème une braise tous
##             les `step` u parcourus (marche ET dash) ; chaque braise est un petit brasier (zone
##             `brasier` marquée `trail`) qui brûle `life` s. Jamais dans l'eau ni sur un obstacle.
##             Améliorations : `life` / `radius` plus grands ; `blastDamage` / `blastRadius` (quand
##             le sillage s'éteint, les braises restantes explosent, une fois par ennemi).
##   sceau   — Stigmate (recharge) : un trait qui MARQUE le premier ennemi touché (`duration` s) ;
##             s'il meurt marqué, il explose (`damage` × `blastMult` à `radius` u). La marque est
##             posée AVANT les dégâts du trait : un ennemi achevé par le trait explose.
##             Améliorations : `contagion` (l'explosion marque ses survivants) ; `healOnBlast` /
##             `refund` (soin, et recharge réduite quand le marqué explose).
##   riposte — Contre-taille (recharge) : une taillade, puis `window` s de garde : le premier coup
##             reçu est PARÉ (aucun dégât) et rendu — `damage` × `riposteMult` à `radius` u,
##             étourdit `stun` s ; le tir paré est détruit.
##             Améliorations : `mirror` (tir renvoyé au tireur, tirs proches effacés) ; `refund` /
##             `surge` (recharge réduite, élan de dégâts).
## État : player.sillage = {t, x, y, def}, player.parry = {t, def, slot} ; un ennemi marqué porte
## e.stigmate = {t, max, damage, radius, contagion, heal, refund, slot}.

const MUZZLE := 0.5 # × rayon du héros : point de départ d'un tir (comme D6KitShots)
const RETURN_SPEED := 1100.0 # u/s : le tir renvoyé par « Miroir » (réglage technique : il doit rattraper un tireur)
const RETURN_RANGE := 900.0 # u
const RETURN_RADIUS := 9.0 # u

# ---------------------------------------------------------------- Sillage de braise

static func use_sillage(game: Dictionary, g: Dictionary) -> void:
	var p: Dictionary = game.player
	p.sillage = {"t": g.duration, "x": p.x, "y": p.y, "def": g}
	_ember(game, g, p.x, p.y)

## Une braise au sol : un petit brasier. Rien n'apparaît dans une rivière, sur un obstacle bas ni
## dans un mur (le dash passe au-dessus de l'eau : il n'y sème rien).
static func _ember(game: Dictionary, g: Dictionary, x: float, y: float) -> void:
	if D6Physics.ground_blocked(game.room, x, y, 0.0):
		return
	var fire: Dictionary = game.tuning.skills.brasier
	D6KitZones.spawn_zone(game, {
		"kind": "brasier", "trail": true, "x": x, "y": y, "r": g.radius, "duration": g.life, "tick": fire.tick, "tickT": 0.0,
		"burnDps": g.burnDps, "burnRefresh": fire.burnRefresh,
	})

static func tick_sillage(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var s = p.get("sillage")
	if s == null:
		return
	var g: Dictionary = s.def
	s.t -= dt
	if D6Geo.dist2(p.x, p.y, s.x, s.y) >= g.step * g.step:
		s.x = p.x
		s.y = p.y
		_ember(game, g, p.x, p.y)
	if s.t > 0.0:
		return
	p.sillage = null
	_detonate(game, g)
	D6State.emit(game, "sillageEnd", {"x": p.x, "y": p.y})

## « Détonation » (amélioration) : les braises encore allumées explosent ; un ennemi pris dans
## plusieurs souffles n'est blessé qu'UNE fois.
static func _detonate(game: Dictionary, g: Dictionary) -> void:
	if g.get("blastDamage") == null:
		return
	var embers: Array = D6KitZones.zones_of(game, "brasier").filter(func(z): return D6Js.truthy(z.get("trail")))
	for z in embers:
		z.dead = true
		D6State.emit(game, "explode", {"x": z.x, "y": z.y, "r": g.blastRadius, "hero": true, "kind": "sillage"})
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		for z in embers:
			var rr: float = g.blastRadius + e.r
			var d2 := D6Geo.dist2(z.x, z.y, e.x, e.y)
			if d2 < rr * rr:
				var l := maxf(1e-6, sqrt(d2))
				D6Combat.damage_enemy(game, e, {"kind": "gadget", "amount": g.blastDamage, "dirX": (e.x - z.x) / l, "dirY": (e.y - z.y) / l, "knockback": g.knockback, "canCrit": false})
				break

# ---------------------------------------------------------------- Stigmate

static func release_sceau(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	D6KitShots.spawn_shot(game, {
		"kind": "stigmate", "x": p.x + p.castDirX * p.r * MUZZLE, "y": p.y + p.castDirY * p.r * MUZZLE,
		"vx": p.castDirX * s.speed, "vy": p.castDirY * s.speed, "r": s.shotRadius, "range": s.range, "damage": s.damage, "source": "skill",
		"knockback": s.knockback, "hitstop": s.hitstop,
		"mark": {
			"kind": "stigmate", "t": s.duration, "max": s.duration, "damage": s.damage * s.blastMult, "radius": s.radius,
			"contagion": D6Js.truthy(s.get("contagion")), "heal": D6Js.nz(s.get("healOnBlast"), 0.0), "refund": D6Js.nz(s.get("refund"), 0.0), "slot": p.castSlot,
		},
	})

## Pose la marque (le trait vient de toucher `e`, ou une explosion contagieuse l'a atteint).
static func brand(game: Dictionary, e: Dictionary, mark: Dictionary) -> void:
	var m: Dictionary = mark.duplicate()
	m.t = m.max
	e.stigmate = m
	D6State.emit(game, "marked", {"id": e.id, "x": e.x, "y": e.y, "mark": "stigmate", "time": m.t})

static func tick_mark(e: Dictionary, dt: float) -> void:
	var m = e.get("stigmate")
	if m == null:
		return
	m.t -= dt
	if m.t <= 0.0:
		e.stigmate = null

## Un ennemi vient de mourir : s'il portait le Stigmate, il explose.
static func on_kill(game: Dictionary, e: Dictionary) -> void:
	var m = e.get("stigmate")
	if m == null:
		return
	e.stigmate = null
	D6State.emit(game, "explode", {"x": e.x, "y": e.y, "r": m.radius, "hero": true, "kind": "stigmate"})
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var o: Dictionary = enemies[i]
		i += 1
		if o.dead or o.spawnT > 0.0:
			continue
		var rr: float = m.radius + o.r
		var d2 := D6Geo.dist2(e.x, e.y, o.x, o.y)
		if d2 >= rr * rr:
			continue
		var l := maxf(1e-6, sqrt(d2))
		D6Combat.damage_enemy(game, o, {"kind": "skill", "amount": m.damage, "dirX": (o.x - e.x) / l, "dirY": (o.y - e.y) / l, "canCrit": false})
		if m.contagion and not o.dead and o.get("stigmate") == null:
			brand(game, o, m) # « Contagion » : le survivant est marqué à son tour
	_harvest(game, m)

## « Moisson » (amélioration) : le marqué qui explose soigne et rend une part de la recharge.
static func _harvest(game: Dictionary, m: Dictionary) -> void:
	if m.heal > 0.0:
		D6Combat.heal_player(game, m.heal, true)
	if m.refund > 0.0 and D6KitSupers.form_of(game) == null: # pendant la forme, le kit d'origine est figé
		var st: Dictionary = game.player.slots[int(m.slot)]
		st.cd *= 1.0 - m.refund

# ---------------------------------------------------------------- Contre-taille

static func release_riposte(game: Dictionary, s: Dictionary, angle: float) -> void:
	var p: Dictionary = game.player
	D6KitCommon.hit_sector(game, p.x, p.y, s.range, angle, s.arc * D6Data.DEG, {
		"kind": "skill", "amount": s.damage, "knockback": s.knockback, "hitstop": s.hitstop, "canCrit": true, "shake": D6Js.nz(s.get("shake"), 0.0),
	})
	p.parry = {"t": s.window, "def": s, "slot": p.castSlot}
	D6State.emit(game, "parryStart", {"x": p.x, "y": p.y, "angle": angle, "arc": s.arc * D6Data.DEG, "range": s.range, "window": s.window})

static func tick_parry(game: Dictionary, dt: float) -> void:
	var st = game.player.get("parry")
	if st == null:
		return
	st.t -= dt
	if st.t <= 0.0:
		game.player.parry = null
		D6State.emit(game, "parryEnd", {"x": game.player.x, "y": game.player.y})

## Un coup va toucher le héros : s'il est en garde, le coup est PARÉ (rend true : aucun dégât) et
## la riposte part. Une seule parade par garde ; de courtes i-frames couvrent les coups simultanés.
static func parry(game: Dictionary, src: Dictionary) -> bool:
	var p: Dictionary = game.player
	var st = p.get("parry")
	if st == null:
		return false
	var s: Dictionary = st.def
	p.parry = null
	p.iframes = maxf(p.iframes, s.parryIframes)
	var sx: float = D6Js.nz(src.get("x"), p.x)
	var sy: float = D6Js.nz(src.get("y"), p.y)
	D6State.emit(game, "parry", {"x": p.x, "y": p.y, "srcX": sx, "srcY": sy, "r": s.radius})
	_kill_shot(game, src.get("id"))
	D6KitCommon.hit_circle(game, p.x, p.y, s.radius, {
		"kind": "skill", "amount": s.damage * s.riposteMult, "knockback": s.knockback, "stun": D6Js.nz(s.get("stun"), 0.0), "hitstop": s.hitstop, "canCrit": true,
	})
	if D6Js.truthy(s.get("mirror")):
		_mirror(game, s, src)
	if s.get("refund") != null and D6KitSupers.form_of(game) == null:
		p.slots[int(st.slot)].cd *= 1.0 - s.refund # « Représailles »
	if s.get("surge") != null:
		p.surge = maxf(p.surge, s.surge)
		p.surgeMult = maxf(p.surgeMult, s.surgeMult)
	return true

## Le tir ennemi qui vient d'être paré est détruit (son identifiant est celui du coup).
static func _kill_shot(game: Dictionary, id) -> void:
	if id == null:
		return
	for pr in game.projectiles:
		if pr.get("owner") == "enemy" and pr.id == id and not D6Js.truthy(pr.get("dead")):
			pr.dead = true
			D6State.emit(game, "deflect", {"x": pr.x, "y": pr.y})

## « Miroir » (amélioration) : les tirs ennemis proches sont effacés, et un trait repart vers le
## tireur (l'ennemi vivant qui a porté le coup), s'il est hors de portée de la riposte.
static func _mirror(game: Dictionary, s: Dictionary, src: Dictionary) -> void:
	var p: Dictionary = game.player
	D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, s.radius)
	var foe = attacker(game, src)
	if foe == null:
		return
	var dx: float = foe.x - p.x
	var dy: float = foe.y - p.y
	var d := sqrt(dx * dx + dy * dy)
	if d <= s.radius + foe.r:
		return
	D6KitShots.spawn_shot(game, {
		"kind": "renvoi", "x": p.x, "y": p.y, "vx": dx / d * RETURN_SPEED, "vy": dy / d * RETURN_SPEED, "r": RETURN_RADIUS, "range": RETURN_RANGE,
		"damage": s.damage * s.riposteMult, "source": "skill", "knockback": s.knockback, "hitstop": s.hitstop,
	})

## L'ennemi vivant qui a porté le coup `src` : celui que nomme `sourceId` (tir, zone), sinon celui
## qui se tient au point d'où vient le coup (mêlée) ; null s'il n'y en a pas.
static func attacker(game: Dictionary, src: Dictionary):
	var id = src.get("sourceId")
	var sx = src.get("x")
	var sy = src.get("y")
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		if D6Js.truthy(id):
			if e.id == id:
				return e
		elif sx != null and sy != null and D6Geo.dist2(e.x, e.y, sx, sy) < 1.0:
			return e
	return null
