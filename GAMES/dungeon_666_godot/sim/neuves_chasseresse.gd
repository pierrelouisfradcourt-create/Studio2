extends RefCounted
## COMPÉTENCES NEUVES DE LA CHASSERESSE (combat V3, étape 4) — chargé par sim/kit_neuves.gd, sans class_name.
## Nombres : data/classes.json (`proie`, `leurre`, `trait`), rangs et améliorations : data/arbres.json.
##
##   proie  — Marque de la proie (recharge) : un trait qui MARQUE le premier ennemi touché pendant
##            `vuln` s : il subit `vulnMult` de dégâts en plus (la vulnérabilité des règles), la
##            visée assistée le préfère (`aimBonus` u retirées à son score, D6Aim) et les limiers
##            de la Meute le prennent pour cible. Améliorations : `jumps` / `jumpRange` (la marque
##            saute sur le plus proche quand la proie meurt) ; `blastRadius` (elle marque aussi
##            tout ce qui entoure le premier touché).
##   leurre — Leurre d'os (à charges) : un mannequin LANCÉ, posé sur la terre ferme (jamais dans
##            l'eau, un mur ni un obstacle : il recule le long du lancer ; sans place, la charge
##            n'est pas dépensée). C'est un ALLIÉ de game.allies (comme les limiers : vagues,
##            ennemis restants et salle nettoyée ne le voient pas) qui ne bouge pas : les ennemis
##            de mêlée en chasse à moins de `radius` u s'y jettent (D6KitSupers.distract), il
##            arrête les tirs et encaisse les zones. `maxActive` au plus. Améliorations :
##            `blastDamage` (il explose, détruit ou à bout de temps) ; `fear` / `hpMult`.
##   trait  — Trait de Nemrod (recharge) : le bouton BANDE l'arc (`castTime` s, état 'cast') ; à
##            pleine charge le trait part seul ; un SECOND appui sur le même bouton le lâche
##            aussitôt, moins fort (de `minCharge` à 1 × `damage`). Un dash ou l'ultime le lâche
##            de même. Sans visée manuelle, il vise au moment de partir. Il traverse tout.
##            Améliorations : `stun` (à pleine charge seulement) ; `castTime` / `range`.
##   grele  — Grêle des Limbes (recharge, étape 5) : elle tire vers le ciel ; `delay` s plus tard les
##            traits tombent à `radius` u autour du point visé (sur la cible si elle est à `range` u,
##            sinon à `throwDist` u ; jamais dans un mur, mais au-dessus de l'eau oui : ce sont des
##            tirs). Ce qui s'y tient ENCORE est frappé : c'est un coup à prévoir. La zone `grele`
##            est le télégraphe (allié). Une grêle tirée tombe même si elle meurt entre-temps.
##            Améliorations : `waves` / `interval` / `waveMult` (elle retombe au même endroit) ;
##            `chill` / `chillMult` (ce qu'elle touche est ralenti).
## Un ennemi marqué porte e.proie = {t, max, aim, jumps, jumpRange, vuln, vulnMult, blastRadius}.

const MUZZLE := 0.5 # × rayon du héros : point de départ d'un tir
const PLACE_STEP := 8.0 # u : pas de recul d'un leurre tombé là où rien ne se pose
const PLACE_MARGIN := 2.0 # u libres autour du leurre posé
const HIT_FLASH := 0.1 # s
static var _point := {"x": 0.0, "y": 0.0}

# ---------------------------------------------------------------- Marque de la proie

static func release_proie(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	D6KitShots.spawn_shot(game, {
		"kind": "marque", "x": p.x + p.castDirX * p.r * MUZZLE, "y": p.y + p.castDirY * p.r * MUZZLE,
		"vx": p.castDirX * s.speed, "vy": p.castDirY * s.speed, "r": s.radius, "range": s.range, "damage": s.damage, "source": "skill",
		"knockback": s.knockback, "hitstop": s.hitstop,
		"mark": {
			"kind": "proie", "t": s.vuln, "max": s.vuln, "aim": s.aimBonus, "vuln": s.vuln, "vulnMult": s.vulnMult,
			"jumps": D6Js.nz(s.get("jumps"), 0.0), "jumpRange": D6Js.nz(s.get("jumpRange"), 0.0), "blastRadius": D6Js.nz(s.get("blastRadius"), 0.0),
		},
	})

## Le trait vient de toucher `e` : il devient la proie ; « Battue » marque aussi ses voisins.
static func brand(game: Dictionary, e: Dictionary, mark: Dictionary) -> void:
	_mark(game, e, mark)
	if mark.blastRadius <= 0.0:
		return
	D6State.emit(game, "kitPulse", {"x": e.x, "y": e.y, "r": mark.blastRadius, "kind": "proie"})
	for o in game.enemies:
		if o.dead or o.spawnT > 0.0 or is_same(o, e):
			continue
		var rr: float = mark.blastRadius + o.r
		if D6Geo.dist2(e.x, e.y, o.x, o.y) < rr * rr:
			_mark(game, o, mark)

static func _mark(game: Dictionary, e: Dictionary, mark: Dictionary) -> void:
	var m: Dictionary = mark.duplicate()
	m.t = m.max
	e.proie = m
	e.vuln = maxf(e.vuln, m.vuln)
	e.vulnMult = maxf(e.vulnMult, m.vulnMult)
	D6State.emit(game, "marked", {"id": e.id, "x": e.x, "y": e.y, "mark": "proie", "time": m.t})

static func tick_mark(e: Dictionary, dt: float) -> void:
	var m = e.get("proie")
	if m == null:
		return
	m.t -= dt
	if m.t <= 0.0:
		e.proie = null

## La proie marquée encore en vie (la première de la salle), ou null : la cible des limiers.
static func prey(game: Dictionary):
	for e in game.enemies:
		if not e.dead and e.spawnT <= 0.0 and e.get("proie") != null:
			return e
	return null

## « Curée » (amélioration) : la proie meurt, la marque saute sur l'ennemi le plus proche.
static func on_kill(game: Dictionary, e: Dictionary) -> void:
	var m = e.get("proie")
	if m == null:
		return
	e.proie = null
	if m.jumps <= 0.0:
		return
	var best = null
	var best_d: float = m.jumpRange * m.jumpRange
	for o in game.enemies:
		if o.dead or o.spawnT > 0.0 or o.get("proie") != null:
			continue
		var d := D6Geo.dist2(e.x, e.y, o.x, o.y)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return
	var next: Dictionary = m.duplicate()
	next.jumps = m.jumps - 1.0
	next.blastRadius = 0.0
	D6State.emit(game, "markJump", {"x0": e.x, "y0": e.y, "x1": best.x, "y1": best.y})
	_mark(game, best, next)

# ---------------------------------------------------------------- Leurre d'os

## Où le leurre se pose : le point du lancer, reculé vers l'héroïne tant que rien ne peut s'y
## poser (mur, pilier, rivière, obstacle bas). Rend null s'il n'y a aucune place jusqu'à elle.
static func _place(game: Dictionary, g: Dictionary, aim_x: float, aim_y: float):
	var p: Dictionary = game.player
	var manual: bool = D6Js.truthy(aim_x) or D6Js.truthy(aim_y)
	var aim: Dictionary = D6Aim.compute_aim(game, aim_x if manual else p.manualAimX, aim_y if manual else p.manualAimY, g.range)
	var dir_x: float = aim.x
	var dir_y: float = aim.y
	var target: Dictionary = D6KitCommon.throw_point(game, dir_x, dir_y, aim.targetId, g.range, g.throwDist, _point)
	var d := sqrt(D6Geo.dist2(p.x, p.y, target.x, target.y))
	while true:
		var x: float = p.x + dir_x * d
		var y: float = p.y + dir_y * d
		if not D6Physics.ground_blocked(game.room, x, y, g.bodyRadius + PLACE_MARGIN):
			return {"x": x, "y": y}
		if d <= 0.0:
			return null
		d = maxf(0.0, d - PLACE_STEP)
	return null

## Pose un leurre. Rend false si rien n'a pu être posé (la charge n'est alors pas dépensée).
static func use_leurre(game: Dictionary, g: Dictionary, aim_x: float, aim_y: float) -> bool:
	var spot = _place(game, g, aim_x, aim_y)
	if spot == null:
		return false
	var mine: Array = game.allies.filter(func(a): return a.kind == "leurre" and not a.dead)
	var i := 0
	while float(mine.size() - i) >= g.maxActive: # au-delà de maxActive, le plus ancien disparaît
		mine[i].dead = true
		mine[i].done = true
		D6State.emit(game, "allyGone", {"id": mine[i].id, "x": mine[i].x, "y": mine[i].y, "reason": "remplace"})
		i += 1
	var hp: float = maxf(1.0, D6Js.jround(g.hp * D6Js.nz(g.get("hpMult"), 1.0) * D6Floors.floor_scaling(game.tuning, game.run.floor).damage))
	var h := {
		"id": D6State.new_id(game), "kind": "leurre", "x": spot.x, "y": spot.y, "vx": 0.0, "vy": 0.0, "r": g.bodyRadius,
		"hp": hp, "maxHp": hp, "life": g.life, "lifeMax": g.life, "state": "post", "targetId": 0.0, "biteT": 0.0,
		"face": game.player.facing, "flash": 0.0, "slot": 0.0, "dead": false, "nav": null,
		"lure": {"range": g.radius, "ratio": g.lureRatio}, "def": g,
	}
	game.allies.append(h)
	D6State.emit(game, "allySpawn", {"id": h.id, "x": h.x, "y": h.y, "life": h.life, "kind": "leurre"})
	if g.get("fear") != null:
		# « Épouvantail » : étourdit sans blesser ce qui est à sa portée (ni Gardien, ni ennemi en garde).
		D6KitCommon.push_circle(game, h.x, h.y, g.radius, 0.0, g.fear)
	return true

## Un pas du leurre (appelé avec les limiers, avant les ennemis) : il ne bouge pas, il s'use.
static func tick_ally(game: Dictionary, h: Dictionary, dt: float) -> void:
	if h.dead:
		if not D6Js.truthy(h.get("done")):
			h.done = true
			_boom(game, h) # détruit par un ennemi depuis le dernier pas
		return
	h.flash = maxf(0.0, h.flash - dt)
	h.life -= dt
	if h.life > 0.0:
		return
	h.dead = true
	h.done = true
	D6State.emit(game, "allyGone", {"id": h.id, "x": h.x, "y": h.y, "reason": "temps"})
	_boom(game, h)

## « Leurre piégé » (amélioration) : détruit ou à bout de temps, il explose.
static func _boom(game: Dictionary, h: Dictionary) -> void:
	var g: Dictionary = h.def
	if g.get("blastDamage") == null:
		return
	D6KitCommon.hit_circle(game, h.x, h.y, g.blastRadius, {"kind": "gadget", "amount": g.blastDamage, "knockback": g.knockback, "stun": D6Js.nz(g.get("blastStun"), 0.0), "hitstop": g.hitstop, "canCrit": false})
	D6State.emit(game, "explode", {"x": h.x, "y": h.y, "r": g.blastRadius, "hero": true, "kind": "leurre"})

# ---------------------------------------------------------------- Trait de Nemrod

## Part de la charge déjà faite, 0..1 (1 = pleine) : lue par l'affichage (slot_view) et au tir.
static func charge_frac(game: Dictionary, s: Dictionary) -> float:
	var p: Dictionary = game.player
	var cast = p.get("cast")
	if cast is Dictionary and cast.get("frac") != null:
		return cast.frac
	return D6Geo.clampv(1.0 - p.castT / maxf(1e-6, s.castTime), 0.0, 1.0)

## L'emplacement `slot` bande-t-il le Trait en ce moment ?
static func charging(game: Dictionary, slot: int) -> bool:
	var p: Dictionary = game.player
	var cast = p.get("cast")
	return p.state == "cast" and int(p.castSlot) == slot and cast is Dictionary and cast.get("kind") == "trait"

## Second appui sur le bouton qui bande : le trait part au prochain pas, à la charge du moment.
static func second_press(game: Dictionary, slot: int) -> bool:
	if not charging(game, slot) or game.player.castT <= 0.0:
		return false
	var p: Dictionary = game.player
	p.cast.frac = charge_frac(game, D6Loadout.cast_def(game))
	p.castT = 0.0
	return true

## Le trait part (pleine charge, second appui, dash ou ultime qui interrompt). Rend l'angle du tir.
static func release_trait(game: Dictionary, s: Dictionary) -> float:
	var p: Dictionary = game.player
	var frac := charge_frac(game, s)
	var cast = p.get("cast")
	var man_x: float = D6Js.nz(cast.get("manX"), 0.0) if cast is Dictionary else 0.0
	var man_y: float = D6Js.nz(cast.get("manY"), 0.0) if cast is Dictionary else 0.0
	var aim: Dictionary = D6Aim.compute_aim(game, man_x, man_y, s.range) # visée assistée : au moment du tir
	p.castDirX = aim.x
	p.castDirY = aim.y
	p.facing = D6Trig.atan2(aim.y, aim.x)
	var full: bool = frac >= 1.0
	var damage: float = s.damage if full else s.damage * (s.minCharge + (1.0 - s.minCharge) * frac)
	D6KitShots.spawn_shot(game, {
		"kind": "trait", "x": p.x + aim.x * p.r * MUZZLE, "y": p.y + aim.y * p.r * MUZZLE, "vx": aim.x * s.speed, "vy": aim.y * s.speed,
		"r": s.radius, "range": s.range, "pierce": s.pierce, "damage": damage, "source": "skill", "knockback": s.knockback, "hitstop": s.hitstop,
		"shake": D6Js.nz(s.get("shake"), 0.0), "stun": D6Js.nz(s.get("stun"), 0.0) if full else 0.0, "heavy": full, "charge": frac,
	})
	D6State.emit(game, "traitShot", {"x": p.x, "y": p.y, "angle": p.facing, "charge": frac, "full": full})
	return p.facing

# ---------------------------------------------------------------- Grêle des Limbes (étape 5)

static func release_grele(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var cast = p.get("cast")
	var target_id = D6Js.nz(cast.get("targetId"), 0.0) if cast is Dictionary else 0.0
	var target: Dictionary = D6KitCommon.throw_point(game, p.castDirX, p.castDirY, target_id, s.range, s.throwDist, _point)
	D6KitZones.spawn_zone(game, {
		"kind": "grele", "x": target.x, "y": target.y, "r": s.radius, "delay": s.delay, "damage": s.damage, "knockback": s.knockback,
		"hitstop": s.hitstop, "shake": D6Js.nz(s.get("shake"), 0.0), "wave": 0.0, "waves": D6Js.nz(s.get("waves"), 1.0),
		"interval": D6Js.nz(s.get("interval"), 0.0), "waveMult": D6Js.nz(s.get("waveMult"), 1.0),
		"chill": D6Js.nz(s.get("chill"), 0.0), "chillMult": D6Js.nz(s.get("chillMult"), 0.0),
	})
	D6State.emit(game, "hailCall", {"x": p.x, "y": p.y, "tx": target.x, "ty": target.y, "r": s.radius, "delay": s.delay})

## Zone `grele` : rien pendant `delay` (le télégraphe), puis la grêle tombe — une fois, ou `waves`
## fois toutes les `interval` s (« Déluge » : les suivantes à `waveMult` des dégâts).
static func zone_grele(game: Dictionary, z: Dictionary) -> void:
	if z.t < z.delay + z.wave * z.interval:
		return
	var amount: float = z.damage * (1.0 if z.wave <= 0.0 else z.waveMult)
	z.wave += 1.0
	if z.wave >= z.waves:
		z.dead = true
	D6State.emit(game, "hail", {"x": z.x, "y": z.y, "r": z.r, "wave": z.wave, "last": z.dead})
	var slow: float = maxf(game.tuning.combat.minChillMult, 1.0 - z.chillMult)
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = z.r + e.r
		var d2 := D6Geo.dist2(z.x, z.y, e.x, e.y)
		if d2 >= rr * rr:
			continue
		var l := maxf(1e-6, sqrt(d2))
		D6Combat.damage_enemy(game, e, {
			"kind": "skill", "amount": amount, "dirX": (e.x - z.x) / l, "dirY": (e.y - z.y) / l, "knockback": z.knockback,
			"hitstop": z.hitstop, "canCrit": true, "shake": z.shake,
		})
		if z.chill > 0.0 and not e.dead: # « Givre des Limbes »
			e.chill = maxf(e.chill, z.chill)
			e.chillMult = minf(e.chillMult if D6Js.truthy(e.get("chillMult")) else 1.0, slow)
