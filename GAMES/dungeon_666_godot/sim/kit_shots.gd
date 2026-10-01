class_name D6KitShots
extends RefCounted
## Portage de src/sim/kit_shots.mjs.
## TIRS DU HÉROS (hors Lance) — traits d'arc, carreaux, épines, crochet de la Chaîne, traits
## de la Nuée. Ils vivent dans game.room.kitFx.shots (kit_common) et portent la SOURCE de
## leurs dégâts : 'melee' / 'strike' pour l'arme (les bénédictions d'attaque s'y appliquent),
## 'skill' pour une compétence, 'super' pour un Super. La Lance, elle, reste un projectile de
## game.projectiles (projectiles), à l'identique.
##
## shot : {id, kind, x, y, vx, vy, r, range, traveled, pierce, hitIds, damage, source,
##         knockback, hitstop, shake, stun, pull?: {stopGap, mass}, heavy, dead}

const MUZZLE := 0.5 # × rayon du héros : point de départ d'un tir (à bout portant, ça touche)

## `ids.includes(id)` : comparaison par `==` (Array.has distingue 1 de 1.0, JavaScript non).
static func _has_id(ids: Array, id) -> bool:
	for v in ids:
		if v == id:
			return true
	return false

## Ajoute un tir du héros dans la salle.
static func spawn_shot(game: Dictionary, s: Dictionary) -> Dictionary:
	var shot := {
		"id": D6State.new_id(game), "kind": "arrow", "traveled": 0.0, "pierce": 0.0, "hitIds": [], "knockback": 0.0, "hitstop": 0.0, "shake": 0.0,
		"stun": 0.0, "pull": null, "heavy": false, "dead": false,
	}
	shot.merge(s, true)
	D6KitCommon.kit_store(game).shots.append(shot)
	return shot

## Tirs d'un coup d'arme à distance (champ `shot` du coup) : `count` projectiles en éventail
## sur `arc` degrés autour de l'angle du coup. Source 'strike' pour la frappe de dash.
static func fire_weapon_shots(game: Dictionary, a: Dictionary) -> void:
	var p: Dictionary = game.player
	var def: Dictionary = a.def
	var sh: Dictionary = def.shot
	var count: float = maxf(1.0, D6Js.nz(sh.get("count"), 1.0))
	var spread: float = D6Js.nz(def.get("arc"), 0.0) * D6Data.DEG
	var i := 0.0
	while i < count:
		var ang: float = a.angle + ((i / (count - 1.0) - 0.5) * spread if count > 1.0 else 0.0)
		var cx: float = D6Trig.cos(ang)
		var cy: float = D6Trig.sin(ang)
		spawn_shot(game, {
			"kind": D6Js.nz(sh.get("kind"), "arrow"),
			"x": p.x + cx * p.r * MUZZLE,
			"y": p.y + cy * p.r * MUZZLE,
			"vx": cx * sh.speed,
			"vy": cy * sh.speed,
			"r": sh.radius,
			"range": def.range,
			"pierce": D6Js.nz(sh.get("pierce"), 0.0),
			"damage": def.damage,
			"source": "strike" if a.strike else "melee",
			"knockback": def.knockback,
			"hitstop": def.hitstop,
			"shake": D6Js.nz(def.get("shake"), 0.0),
			"stun": D6Js.nz(def.get("stun"), 0.0),
			"heavy": D6Js.truthy(sh.get("heavy")) or D6Js.truthy(a.strike),
		})
		i += 1.0

## Tirs en éventail (compétence Volée, etc.) depuis le héros.
static func fire_fan(game: Dictionary, angle: float, count: float, spread_deg: float, spec: Dictionary) -> void:
	var p: Dictionary = game.player
	var spread: float = spread_deg * D6Data.DEG
	var i := 0.0
	while i < count:
		var ang: float = angle + ((i / (count - 1.0) - 0.5) * spread if count > 1.0 else 0.0)
		var cx: float = D6Trig.cos(ang)
		var cy: float = D6Trig.sin(ang)
		var s: Dictionary = spec.duplicate()
		s.x = p.x + cx * p.r * MUZZLE
		s.y = p.y + cy * p.r * MUZZLE
		s.vx = cx * spec.speed
		s.vy = cy * spec.speed
		spawn_shot(game, s)
		i += 1.0

static func update_shots(game: Dictionary, dt: float) -> void:
	var store = game.room.get("kitFx")
	if store == null or store.shots.size() == 0:
		return
	var room: Dictionary = game.room
	var shots: Array = store.shots
	var i := 0
	while i < shots.size():
		var s: Dictionary = shots[i]
		i += 1
		if s.dead:
			continue
		var ox: float = s.x
		var oy: float = s.y
		var speed: float = maxf(1e-6, sqrt(s.vx * s.vx + s.vy * s.vy))
		s.x += s.vx * dt
		s.y += s.vy * dt
		s.traveled += speed * dt
		if s.traveled > s.range or D6Physics.point_blocked(room, s.x, s.y, 0.0):
			s.dead = true
			continue
		_shot_hits(game, s, ox, oy, speed)
	D6Projectiles.compact(store.shots)

## Ennemis traversés par le tir sur le segment parcouru pendant ce pas (corps de la boucle de
## update_shots, sorti pour la longueur : même ordre des effets).
static func _shot_hits(game: Dictionary, s: Dictionary, ox: float, oy: float, speed: float) -> void:
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0 or _has_id(s.hitIds, e.id):
			continue
		var rr: float = s.r + e.r
		# Test sur le segment parcouru : pas de traversée à grande vitesse.
		if D6Geo.point_seg_dist2(e.x, e.y, ox, oy, s.x, s.y) >= rr * rr:
			continue
		s.hitIds.append(e.id)
		D6Combat.damage_enemy(game, e, {
			"kind": s.source, "amount": s.damage, "dirX": s.vx / speed, "dirY": s.vy / speed,
			"knockback": s.knockback, "hitstop": s.hitstop, "canCrit": true, "shake": s.shake, "stun": s.stun,
		})
		if s.pull != null:
			_hook(game, s, e)
		if float(s.hitIds.size()) > s.pierce:
			s.dead = true
			break

## Crochet de la Chaîne d'Enfer : l'ennemi harponné est tiré contre le héros.
static func _hook(game: Dictionary, s: Dictionary, e: Dictionary) -> void:
	var p: Dictionary = game.player
	D6State.emit(game, "hook", {"x0": p.x, "y0": p.y, "x1": e.x, "y1": e.y, "boss": D6Js.truthy(e.get("boss"))})
	if e.dead:
		return
	D6KitCommon.pull_toward(game, e, p.x, p.y, p.r + e.r + s.pull.stopGap, s.pull.mass)
