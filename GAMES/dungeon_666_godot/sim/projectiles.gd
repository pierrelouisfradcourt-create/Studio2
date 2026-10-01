class_name D6Projectiles
extends RefCounted
## Portage de src/sim/projectiles.mjs.
## Projectiles (héros et ennemis) et zones de danger télégraphiées.

const TINY := 1e-6
const BLAST_KNOCKBACK := 260.0 # recul infligé aux ennemis pris dans une explosion

## Champ numérique optionnel : absent ou null → 0 (en JavaScript, `undefined > 0` est faux).
static func _num(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return 0.0 if v == null else float(v)

## `ids.includes(id)` : comparaison par `==` (Array.has distingue 1 de 1.0, JavaScript non).
static func _has_id(ids: Array, id) -> bool:
	for v in ids:
		if v == id:
			return true
	return false

## Source vivante d'une attaque (id d'ennemi), ou null.
static func _source_of(game: Dictionary, id):
	if not D6Js.truthy(id):
		return null
	for e in game.enemies:
		if e.id == id and not e.dead:
			return e
	return null

## Blesse le héros au nom d'un ennemi (élite vampirique : se soigne de ce qui a porté).
static func _hurt_player_for(game: Dictionary, source_id, amount: float, src: Dictionary) -> bool:
	var p: Dictionary = game.player
	var hp0: float = p.hp
	var landed: bool = D6Combat.damage_player(game, amount, src)
	if landed and D6Js.truthy(source_id):
		D6FoeElites.foe_dealt(game, _source_of(game, source_id), hp0 - p.hp)
	return landed

## p : {owner: 'player'|'enemy', kind, x, y, vx, vy, r, damage, range, pierce, knockback,
##      hitstop, sourceId}
static func spawn_projectile(game: Dictionary, p: Dictionary) -> Dictionary:
	var pr := {"id": D6State.new_id(game), "hitIds": [], "traveled": 0.0, "pierce": 0.0, "knockback": 0.0, "hitstop": 0.0, "sourceId": 0.0}
	pr.merge(p, true)
	game.projectiles.append(pr)
	return pr

## Détruit les projectiles ennemis dans un cercle (nova, Super) ; rend leur nombre.
static func destroy_enemy_projectiles_in_circle(game: Dictionary, x: float, y: float, r: float) -> float:
	var n := 0.0
	for pr in game.projectiles:
		if pr.get("owner") != "enemy" or D6Js.truthy(pr.get("dead")):
			continue
		var rr: float = r + pr.r
		if D6Geo.dist2(x, y, pr.x, pr.y) < rr * rr:
			pr.dead = true
			n += 1.0
			D6State.emit(game, "deflect", {"x": pr.x, "y": pr.y})
	return n

## Un projectile du héros contre les ennemis : test sur le segment parcouru (ox, oy) → (x, y).
static func _player_projectile_hits(game: Dictionary, pr: Dictionary, ox: float, oy: float) -> void:
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0 or _has_id(pr.hitIds, e.id):
			continue
		var rr: float = pr.r + e.r
		if D6Geo.point_seg_dist2(e.x, e.y, ox, oy, pr.x, pr.y) < rr * rr:
			pr.hitIds.append(e.id)
			var l := maxf(TINY, sqrt(pr.vx * pr.vx + pr.vy * pr.vy))
			D6Combat.damage_enemy(game, e, {
				"kind": "skill", "amount": pr.get("damage"), "dirX": pr.vx / l, "dirY": pr.vy / l,
				"knockback": pr.knockback, "hitstop": pr.hitstop, "canCrit": true,
			})
			if pr.hitIds.size() > pr.pierce:
				pr.dead = true
				break

static func update_projectiles(game: Dictionary, dt: float) -> void:
	var room: Dictionary = game.room
	var p: Dictionary = game.player
	var projectiles: Array = game.projectiles
	var i := 0
	while i < projectiles.size():
		var pr: Dictionary = projectiles[i]
		i += 1
		if D6Js.truthy(pr.get("dead")):
			continue
		var ox: float = pr.x
		var oy: float = pr.y
		pr.x += pr.vx * dt
		pr.y += pr.vy * dt
		pr.traveled += sqrt(pr.vx * pr.vx + pr.vy * pr.vy) * dt
		var max_travel = pr.get("range")
		if (max_travel != null and pr.traveled > max_travel) or D6Physics.point_blocked(room, pr.x, pr.y, 0.0):
			pr.dead = true
			D6State.emit(game, "projectileEnd", {"x": pr.x, "y": pr.y, "owner": pr.get("owner"), "kind": pr.get("kind")})
			continue
		if pr.get("owner") == "enemy":
			if p.state == "dead":
				continue
			var rr: float = pr.r + p.r
			# Test sur le segment parcouru : pas de traversée à grande vitesse.
			if D6Geo.point_seg_dist2(p.x, p.y, ox, oy, pr.x, pr.y) < rr * rr:
				var landed := _hurt_player_for(game, pr.sourceId, pr.get("damage"), {"kind": pr.get("kind"), "id": pr.id, "x": pr.x, "y": pr.y})
				if landed:
					pr.dead = true
		else:
			_player_projectile_hits(game, pr, ox, oy)
	compact(projectiles)

static func _in_hazard(h: Dictionary, x: float, y: float, r: float) -> bool:
	if h.shape == "circle":
		var rr: float = h.r + r
		return D6Geo.dist2(x, y, h.x, h.y) < rr * rr
	if h.shape == "ring":
		var d := sqrt(D6Geo.dist2(x, y, h.x, h.y))
		return d < h.r + r and d > h.inner - r
	# 'line' : RECTANGLE partant de (x, y) dans la direction `angle`, long de `length`, large de
	# `width` — exactement ce que dessine le rendu (render.mjs drawLine). Un corps de rayon r est
	# touché s'il mord sur ce rectangle, pas au-delà : le bord dessiné est le bord qui touche
	# (une brèche dessinée est une vraie brèche, le dos d'une frappe en ligne est sûr).
	var d2 := D6Geo.point_band_dist2(x, y, h.x, h.y, h.angle, h.length, h.width)
	return d2 == 0.0 or d2 < r * r

## Zone PERSISTANTE (h.linger > 0, ex. flamme de la Pyromancienne) : une fois allumée — donc
## TOUJOURS après son télégraphe —, elle brûle `linger` s et blesse le héros de `tickDamage`
## toutes les `tickEvery` s, SEULEMENT s'il est à l'intérieur. Sa source peut mourir : la flaque
## reste (elle est au sol). Elle s'éteint quand la salle est nettoyée. Les i-frames (dash, coup
## reçu) protègent sans compter d'esquive : traverser une flaque n'est pas une esquive parfaite.
static func _burn_hazard(game: Dictionary, h: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	h.burnT += dt
	if h.burnT >= h.linger or D6Js.truthy(game.room.get("cleared")):
		h.done = true
		return
	h.tickT += dt
	if h.tickT < h.tickEvery:
		return
	h.tickT -= h.tickEvery
	if not D6Js.truthy(h.get("hitsPlayer")) or p.state == "dead" or p.iframes > 0.0 or not _in_hazard(h, p.x, p.y, p.r):
		return
	_hurt_player_for(game, h.get("sourceId"), h.tickDamage, {"kind": h.get("kind"), "id": h.id, "x": h.x, "y": h.y})

## Vrai si la source d'une zone en télégraphe est morte, absente ou étourdie (attaque annulée).
static func _source_lost(game: Dictionary, source_id) -> bool:
	var src = null
	for e in game.enemies:
		if e.id == source_id:
			src = e
			break
	return src == null or src.dead or src.stun > 0.0

## Frappe d'une zone dont le télégraphe s'achève : le héros d'abord, puis les ennemis.
static func _fire_hazard(game: Dictionary, h: Dictionary) -> void:
	var p: Dictionary = game.player
	D6State.emit(game, "hazardFire", {
		"id": h.id, "kind": h.get("kind"), "shape": h.shape, "x": h.x, "y": h.y, "r": h.get("r"),
		"angle": h.get("angle"), "length": h.get("length"), "width": h.get("width"),
	})
	if D6Js.truthy(h.get("hitsPlayer")) and p.state != "dead" and _in_hazard(h, p.x, p.y, p.r):
		_hurt_player_for(game, h.get("sourceId"), h.get("damage"), {"kind": h.get("kind"), "id": h.id, "x": h.x, "y": h.y})
	if D6Js.truthy(h.get("hitsEnemies")):
		var owner_id = h.get("ownerId")
		var enemies: Array = game.enemies
		var i := 0
		while i < enemies.size():
			var e: Dictionary = enemies[i]
			i += 1
			if e.dead or e.spawnT > 0.0 or (owner_id != null and e.id == owner_id):
				continue
			if _in_hazard(h, e.x, e.y, e.r):
				var dx: float = e.x - h.x
				var dy: float = e.y - h.y
				var l := maxf(TINY, sqrt(dx * dx + dy * dy))
				# Une explosion d'ENNEMI (Possédé) ne profite ni de l'arme ni des bonus du héros.
				D6Combat.damage_enemy(game, e, {
					"kind": "enemyBlast" if D6Js.truthy(owner_id) else "blast", "amount": h.get("damage"),
					"dirX": dx / l, "dirY": dy / l, "knockback": BLAST_KNOCKBACK, "canCrit": false,
				})

static func update_hazards(game: Dictionary, dt: float) -> void:
	var hazards: Array = game.hazards
	# Boucle à index : une zone née pendant la boucle (explosion à la mort d'un ennemi) est vue
	# dans la même passe, comme par le `for…of` du JavaScript.
	var i := 0
	while i < hazards.size():
		var h: Dictionary = hazards[i]
		i += 1
		if h.done:
			continue
		if D6Js.truthy(h.get("burning")):
			_burn_hazard(game, h, dt)
			continue
		# Source morte ou étourdie pendant le télégraphe : l'attaque est annulée (punition récompensée).
		if D6Js.truthy(h.get("sourceId")):
			if _source_lost(game, h.sourceId):
				h.done = true
				D6State.emit(game, "hazardCancel", {"id": h.id, "x": h.x, "y": h.y})
				continue
		h.t += dt
		var delay = h.get("delay")
		if delay != null and h.t < delay:
			continue
		if _num(h, "linger") > 0.0:
			# Allumage d'une zone persistante : elle frappe comme les autres, puis reste au sol.
			h.burning = true
			h.burnT = 0.0
			h.tickT = 0.0
		else:
			h.done = true
		_fire_hazard(game, h)
	_compact_done(hazards)

## Retire en place les éléments `dead` (pas d'allocation).
static func compact(arr: Array) -> void:
	var w := 0
	for i in range(arr.size()):
		if not D6Js.truthy(arr[i].get("dead")):
			arr[w] = arr[i]
			w += 1
	arr.resize(w)

static func _compact_done(arr: Array) -> void:
	var w := 0
	for i in range(arr.size()):
		if not D6Js.truthy(arr[i].get("done")):
			arr[w] = arr[i]
			w += 1
	arr.resize(w)

## Progression 0..1 du télégraphe d'une zone (pour le rendu).
static func hazard_progress(h: Dictionary) -> float:
	return minf(1.0, h.t / h.delay) if _num(h, "delay") > 0.0 else 1.0

## Part 0..1 de vie restante d'une zone persistante allumée (1 = vient de s'allumer, 0 =
## éteinte). Le rendu la DESSINE (la flaque se résorbe) : c'est ce que lit l'œil du joueur.
static func linger_left(h: Dictionary) -> float:
	return maxf(0.0, 1.0 - h.burnT / h.linger) if D6Js.truthy(h.get("burning")) and _num(h, "linger") > 0.0 else 0.0
