extends RefCounted
## ULTIME « INVOCATION » — Meute des Limbes (Chasseresse). Chargé par D6KitSupers (pas de class_name).
## Données : tuning.supers.meute_limbes (data/classes.json).
##
## Les LIMIERS vivent dans game.allies (JAMAIS dans game.enemies : vagues, « ennemis restants »,
## salle nettoyée, invocations et élites ne les voient pas). Un limier :
##   {id, kind: 'limier', x, y, vx, vy, r, hp, maxHp, life, lifeMax, state: 'heel' | 'chase' | 'bite',
##    targetId, biteT, face, flash, slot, dead, nav}
## Règles :
##   - `count` limiers apparaissent autour de l'héroïne, sur la terre ferme, là où elle peut marcher
##     tout droit (jamais dans un mur, un pilier, une rivière, ni de l'autre côté de l'eau) ;
##   - cible : ce que l'héroïne vient de BLESSER elle-même (player.markId, `markTime` s), sinon ce
##     qu'elle vient de VISER (player.lastTargetId), sinon l'ennemi le plus proche du limier ;
##   - ils MARCHENT (collision de marche : ni mur, ni pilier, ni terrain bas) et CONTOURNENT par les
##     gués : chacun suit son propre champ de navigation vers sa cible (D6Nav.flood_to) ;
##   - morsure au contact, toutes les `biteEvery` s : source 'ally' (dégâts à l'échelle de l'arme
##     comme tout coup du héros, « Gloire charnelle » comprise ; ni jauge d'ultime, ni proc « au
##     toucher », ni vol de vie ; la MORT d'un ennemi compte : or, Âmes, procs « à la mort », salle) ;
##   - ils encaissent : un ennemi de MÊLÉE en chasse se tourne vers le limier qui est nettement plus
##     près que l'héroïne (à moins de `distractRange` u, de `distractRatio` × sa distance à elle, et
##     atteignable à pied tout droit) et le frappe au contact à son rythme (ses dégâts, sa recharge) ;
##     un tir ennemi qui touche un limier s'y arrête ; une zone qui frappe le héros frappe aussi les
##     limiers qui s'y trouvent ;
##   - ils disparaissent à la fin de `life`, à leur mort, à la mort de l'héroïne, au changement de salle.
## Tant qu'un limier vit, la jauge d'ultime est leur minuterie (elle se vide) et ne se remplit pas.
##
## AUTRES ALLIÉS (étape 4) : le LEURRE de la Chasseresse vit dans la même liste (mêmes gardes :
## jamais un ennemi) et profite des mêmes règles d'encaissement — un ennemi de mêlée s'y jette
## (son champ `lure` = {range, ratio} remplace distractRange / distractRatio), un tir s'y arrête,
## une zone le blesse. Il n'est PAS un ultime : il ne tient pas la jauge, ne bloque pas le lancer
## (hounds, any_hound), et son pas est joué par Neuves.tick_ally.
## L'OMBRE JUMELLE du Revenant (étape 5) y vit aussi, marquée `ghost` : INTANGIBLE — aucun ennemi ne
## se tourne vers elle, aucun tir ne s'y arrête, rien ne la blesse (_lure, block_shot, hurt).

const SPREAD := 0.9 # rad entre deux limiers à l'apparition (derrière l'héroïne, en éventail)
const SPAWN_RINGS := [1.0, 0.66, 0.33] # parts de spawnDist essayées, du plus loin au plus près
const SPAWN_TURNS := 8 # directions essayées par anneau
const SPAWN_MARGIN := 2.0 # u libres autour d'un limier qui apparaît
const NAV_REFRESH := 15.0 # pas entre deux calculs du champ d'un limier (comme D6Nav)
const CONTACT := 8.0 # u : marge de contact d'un ennemi qui frappe un limier
const HEEL_STOP := 0.6 # part de heelDist où le limier au pied s'arrête
const HIT_FLASH := 0.1 # s : éclat d'un limier touché
const HOUND := "limier" # game.allies porte aussi d'autres alliés (le leurre, étape 4 : sim/kit_neuves.gd)
const Neuves := preload("res://sim/kit_neuves.gd")

static var _dir := {"x": 0.0, "y": 0.0}

## Réglages de la Meute : le Super actif si c'est elle, sinon la première de la table (tests).
static func def_of(game: Dictionary):
	var s = game.tuning.get("super")
	if s is Dictionary and s.get("kind") == "meute":
		return s
	for id in game.tuning.supers:
		if game.tuning.supers[id].get("kind") == "meute":
			return game.tuning.supers[id]
	return null

## Fait apparaître la meute autour de l'héroïne.
static func summon(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var life: float = s.life + D6Js.nz(p.stats.get("superDurationBonus"), 0.0)
	var hp: float = maxf(1.0, D6Js.jround(s.hp * D6Floors.floor_scaling(game.tuning, game.run.floor).damage))
	var n := int(s.count)
	for i in n:
		var pt := _spawn_point(game, s, p.facing + PI + (float(i) - float(n - 1) / 2.0) * SPREAD)
		var h := {
			"id": D6State.new_id(game), "kind": "limier", "x": pt.x, "y": pt.y, "vx": 0.0, "vy": 0.0, "r": s.houndRadius,
			"hp": hp, "maxHp": hp, "life": life, "lifeMax": life, "state": "heel", "targetId": 0.0, "biteT": 0.0,
			"face": p.facing, "flash": 0.0, "slot": float(i), "dead": false, "nav": null,
		}
		game.allies.append(h)
		D6State.emit(game, "allySpawn", {"id": h.id, "x": h.x, "y": h.y, "life": life})

## Point d'apparition d'un limier dans la direction `angle` : terre ferme, hors des murs et des
## piliers, joignable à pied tout droit depuis l'héroïne. À défaut : sa place à elle (terre ferme).
static func _spawn_point(game: Dictionary, s: Dictionary, angle: float) -> Dictionary:
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	var r: float = s.houndRadius
	for ring in SPAWN_RINGS:
		for k in SPAWN_TURNS:
			# 0, +1, −1, +2, −2… huitièmes de tour autour de la direction voulue
			@warning_ignore("integer_division")
			var turn: float = float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
			var a: float = angle + turn * (PI * 2.0 / float(SPAWN_TURNS))
			var x: float = p.x + D6Trig.cos(a) * s.spawnDist * ring
			var y: float = p.y + D6Trig.sin(a) * s.spawnDist * ring
			if D6Physics.ground_blocked(room, x, y, r + SPAWN_MARGIN):
				continue
			if D6Physics.walk_clear(room, p.x, p.y, x, y, r):
				return {"x": x, "y": y}
	return {"x": p.x, "y": p.y}

## Un pas de la meute (après le héros, avant les ennemis).
static func tick(game: Dictionary, dt: float) -> void:
	var allies: Array = game.allies
	if allies.is_empty():
		return
	var p: Dictionary = game.player
	if p.state == "dead":
		dismiss(game, "mort")
		return
	var pack := any_hound(game)
	var s = def_of(game)
	var mark = _marked(game, s) if pack else null
	var left := 0.0
	var i := 0
	while i < allies.size():
		var h: Dictionary = allies[i]
		i += 1
		if h.kind != HOUND:
			Neuves.tick_ally(game, h, dt) # le leurre : il ne bouge pas, il s'use
			continue
		if not h.dead:
			_tick_hound(game, h, s, mark, dt)
		if not h.dead:
			left = maxf(left, h.life / h.lifeMax)
	_separate(game)
	D6Projectiles.compact(allies)
	if pack:
		p.superCharge = left # la jauge est leur minuterie

## Retire toute la meute (mort de l'héroïne, changement de salle, reprise).
static func dismiss(game: Dictionary, reason: String) -> void:
	for h in game.allies:
		if not h.dead:
			D6State.emit(game, "allyGone", {"id": h.id, "x": h.x, "y": h.y, "reason": reason})
	if any_hound(game):
		game.player.superCharge = 0.0
	game.allies.clear()

## Un limier au moins est-il dans la liste des alliés ? (un leurre n'est pas la meute)
static func any_hound(game: Dictionary) -> bool:
	for h in game.allies:
		if h.kind == HOUND:
			return true
	return false

## Nombre de limiers de la liste des alliés.
static func hounds(game: Dictionary) -> float:
	var n := 0.0
	for h in game.allies:
		if h.kind == HOUND:
			n += 1.0
	return n

## La cible désignée par l'héroïne : ce qu'elle vient de blesser, sinon ce qu'elle vient de viser.
static func _marked(game: Dictionary, s: Dictionary):
	var p: Dictionary = game.player
	var prey = Neuves.prey(game)
	if prey != null:
		return prey # Marque de la proie (étape 4) : la proie marquée passe avant tout
	if game.time - D6Js.nz(p.get("markAt"), -99.0) <= s.markTime:
		var e = D6KitCommon.live_enemy(game, p.get("markId"))
		if e != null:
			return e
	if game.time - D6Js.nz(p.get("lastTargetAt"), -99.0) <= s.markTime:
		return D6KitCommon.live_enemy(game, p.get("lastTargetId"))
	return null

## L'ennemi vivant le plus proche du limier (à égalité : le premier de la liste), ou null.
static func _nearest(game: Dictionary, h: Dictionary):
	var best = null
	var best_d := INF
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		var d := D6Geo.dist2(h.x, h.y, e.x, e.y)
		if d < best_d:
			best_d = d
			best = e
	return best

static func _tick_hound(game: Dictionary, h: Dictionary, s: Dictionary, mark, dt: float) -> void:
	h.flash = maxf(0.0, h.flash - dt)
	h.biteT = maxf(0.0, h.biteT - dt)
	h.life -= dt
	if h.life <= 0.0:
		h.dead = true
		D6State.emit(game, "allyGone", {"id": h.id, "x": h.x, "y": h.y, "reason": "temps"})
		return
	var e = mark if mark != null else _nearest(game, h)
	h.targetId = e.id if e != null else 0.0
	if e == null:
		_heel(game, h, s, dt)
		return
	var dx: float = e.x - h.x
	var dy: float = e.y - h.y
	var d: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	h.face = D6Trig.atan2(dy, dx)
	if d > h.r + e.r + s.biteRange:
		h.state = "chase"
		_run(game, h, e.x, e.y, s.speed, dt)
		return
	h.state = "bite"
	h.vx = 0.0
	h.vy = 0.0
	if h.biteT > 0.0:
		return
	h.biteT = s.biteEvery
	D6State.emit(game, "allyBite", {"id": h.id, "x": h.x, "y": h.y, "tx": e.x, "ty": e.y, "angle": h.face})
	D6Combat.damage_enemy(game, e, {"kind": "ally", "amount": s.biteDamage, "dirX": dx / d, "dirY": dy / d, "knockback": s.biteKnockback, "canCrit": false})

## Sans cible : le limier revient au pied de l'héroïne.
static func _heel(game: Dictionary, h: Dictionary, s: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	h.state = "heel"
	h.vx = 0.0
	h.vy = 0.0
	if D6Geo.dist2(h.x, h.y, p.x, p.y) > s.heelDist * s.heelDist * HEEL_STOP * HEEL_STOP:
		h.face = D6Trig.atan2(p.y - h.y, p.x - h.x)
		if D6Geo.dist2(h.x, h.y, p.x, p.y) > s.heelDist * s.heelDist:
			_run(game, h, p.x, p.y, s.speed, dt)

## Court vers (x, y) : tout droit si l'on peut y marcher, sinon par son champ de navigation
## (piliers et terrain bas contournés, par les gués). La collision de marche a le dernier mot.
static func _run(game: Dictionary, h: Dictionary, x: float, y: float, speed: float, dt: float) -> void:
	var dx: float = x - h.x
	var dy: float = y - h.y
	var d: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	h.vx = (dx / d) * speed
	h.vy = (dy / d) * speed
	if not D6Physics.walk_clear(game.room, h.x, h.y, x, y, h.r) and _nav_dir(game, h, x, y):
		h.vx = _dir.x * speed
		h.vy = _dir.y * speed
	D6Physics.move_circle(game.room, h, h.vx * dt, h.vy * dt)

## Pente du champ de navigation du limier vers (x, y), recalculé quand la cible change de case ou
## toutes les NAV_REFRESH images. Écrit _dir ; false si aucune pente (poursuite directe).
static func _nav_dir(game: Dictionary, h: Dictionary, x: float, y: float) -> bool:
	var room: Dictionary = game.room
	if room.get("nav") == null:
		return false
	var cell := D6Nav.cell_of(room, x, y)
	var f = h.get("nav")
	if f == null or f.cell != cell or game.tick - f.tick >= NAV_REFRESH:
		f = {"cell": cell, "tick": game.tick, "dist": D6Nav.flood_to(room, x, y)}
		h.nav = f
	return D6Nav.slope(room.nav, f.dist, h.x, h.y, _dir)

## Les limiers ne s'empilent pas : deux qui se chevauchent s'écartent à parts égales, puis la
## collision de marche repasse (jamais dans un mur, jamais dans l'eau).
static func _separate(game: Dictionary) -> void:
	var allies: Array = game.allies
	for i in allies.size():
		var a: Dictionary = allies[i]
		if a.dead or a.kind != HOUND:
			continue
		for j in range(i + 1, allies.size()):
			var b: Dictionary = allies[j]
			if b.dead or b.kind != HOUND: # un leurre est planté : il ne pousse ni n'est poussé
				continue
			var dx: float = b.x - a.x
			var dy: float = b.y - a.y
			var rr: float = a.r + b.r
			var d2: float = dx * dx + dy * dy
			if d2 >= rr * rr or d2 < 1e-9:
				continue
			var d: float = sqrt(d2)
			var push: float = (rr - d) / d * 0.5
			a.x -= dx * push
			a.y -= dy * push
			b.x += dx * push
			b.y += dy * push
	for h in allies:
		if not h.dead and h.kind == HOUND:
			D6Physics.move_circle(game.room, h, 0.0, 0.0)

## Blesse un limier (coup d'ennemi, tir, zone). Rend true s'il était vivant.
static func hurt(game: Dictionary, h: Dictionary, amount: float, source) -> bool:
	if h.dead or D6Js.truthy(h.get("ghost")):
		return false
	var dmg: float = maxf(1.0, D6Js.jround(amount))
	h.hp -= dmg
	h.flash = HIT_FLASH
	D6State.emit(game, "allyHurt", {"id": h.id, "x": h.x, "y": h.y, "amount": dmg, "source": source})
	if h.hp <= 0.0:
		h.hp = 0.0
		h.dead = true
		D6State.emit(game, "allyDeath", {"id": h.id, "x": h.x, "y": h.y})
	return true

## Le limier vers lequel l'ennemi `e` se tourne (règle de distraction), ou null.
static func _lure(game: Dictionary, e: Dictionary, s: Dictionary):
	var p: Dictionary = game.player
	var to_hero: float = sqrt(D6Geo.dist2(e.x, e.y, p.x, p.y))
	var best = null
	var best_d := INF
	for h in game.allies:
		if h.dead or D6Js.truthy(h.get("ghost")):
			continue
		# Portée d'attirance de CET allié : celle des limiers, ou la sienne (`lure` du leurre).
		var lure = h.get("lure")
		var limit: float = minf(lure.range, to_hero * lure.ratio) if lure is Dictionary else minf(s.distractRange, to_hero * s.distractRatio)
		var d := D6Geo.dist2(e.x, e.y, h.x, h.y)
		if d < limit * limit and d < best_d and D6Physics.walk_clear(game.room, e.x, e.y, h.x, h.y, e.r):
			best_d = d
			best = h
	return best

## Un ennemi de mêlée en chasse est-il accaparé par un limier ? Si oui, il joue ICI son pas (marche
## vers le limier, le frappe au contact quand sa recharge est finie) et l'IA de l'archétype est
## sautée (rend true). e.allyId dit à l'affichage vers qui il s'est tourné (0 = personne).
static func distract(game: Dictionary, e: Dictionary, def: Dictionary) -> bool:
	var h = null
	if e.state == "chase" and D6AiCommon.melee_kinds().has(e.kind) and D6Js.nz(def.get("damage"), 0.0) > 0.0:
		h = _lure(game, e, def_of(game))
	if h == null:
		if e.has("allyId"):
			e.allyId = 0.0
		return false
	e.allyId = h.id
	var dx: float = h.x - e.x
	var dy: float = h.y - e.y
	var d: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	e.dirX = dx / d
	e.dirY = dy / d
	if d > e.r + h.r + CONTACT:
		var speed := D6AiCommon.speed_of(game, e, def)
		e.vx = e.dirX * speed
		e.vy = e.dirY * speed
	elif e.cooldown <= 0.0:
		e.cooldown = D6AiCommon.recharge_of(game, e, def)
		D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind, "ally": h.id})
		hurt(game, h, def.damage * e.dmgScale, e.kind)
	return true

## Un tir ennemi qui vient de parcourir (ox, oy) → (pr.x, pr.y) touche-t-il un limier ? Il le
## blesse et s'y arrête (rend true).
static func block_shot(game: Dictionary, pr: Dictionary, ox: float, oy: float) -> bool:
	for h in game.allies:
		if h.dead or D6Js.truthy(h.get("ghost")):
			continue
		var rr: float = pr.r + h.r
		if D6Geo.point_seg_dist2(h.x, h.y, ox, oy, pr.x, pr.y) < rr * rr:
			hurt(game, h, D6Js.nz(pr.get("damage"), 0.0), pr.get("kind"))
			D6State.emit(game, "projectileEnd", {"x": pr.x, "y": pr.y, "owner": "enemy", "kind": pr.get("kind")})
			return true
	return false
