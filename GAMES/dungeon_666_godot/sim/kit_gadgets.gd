class_name D6KitGadgets
extends RefCounted
## Portage de src/sim/kit_gadgets.mjs.
## GADGETS autres que la Nova de cendres, joués selon `kind` (charges par section, comme la Nova) :
##   bombe — lancée sur l'ennemi visé (ou devant soi), explose après une courte mèche
##   piege — posé aux pieds ; se referme sur le premier ennemi qui passe (maxActive au plus)
##   totem — posé aux pieds ; impulsions qui blessent et ralentissent
##   cri   — hurlement autour du héros : étourdit et rend vulnérable, sans repousser
## player vérifie que le gadget est utilisable (ni mort, ni Super, une charge au moins) et donne
## l'emplacement `slot` d'où il part, avec la visée de son bouton (0, 0 = celle de l'attaque).
## Les AMÉLIORATIONS EXCLUSIVES de l'arbre (sim/tree.gd) ajoutent des nombres au gadget : `count` /
## `spread` (bombes en grappe), `count` / `ringDist` (champ de pièges), `ward` (totem gardien),
## `surge` (cri de guerre), `pullGap` / `pullMass` et `fireDuration` / `fireDps` (nova : player).

static var _point := {"x": 0.0, "y": 0.0}

static func use_kit_gadget(game: Dictionary, g: Dictionary, slot: int, aim_x: float = 0.0, aim_y: float = 0.0) -> bool:
	var p: Dictionary = game.player
	var st: Dictionary = p.slots[slot]
	st.charges -= 1.0
	if D6Js.truthy(g.get("iframes")):
		p.iframes = maxf(p.iframes, g.iframes)
	match g.kind:
		"bombe":
			_throw_bombs(game, g, aim_x, aim_y)
		"piege":
			_lay_traps(game, g)
		"cri":
			_roar(game, g)
		"totem":
			D6KitZones.spawn_zone(game, {
				"kind": "totem", "x": p.x, "y": p.y, "r": g.radius, "life": g.life, "pulse": g.pulse, "pulseT": 0.0, "damage": g.damage,
				"chill": g.chill, "chillMult": g.chillMult, "ward": D6Js.truthy(g.get("ward")),
			})
	game.telemetry.gadgetUses += 1.0
	D6State.emit(game, "gadget", {"x": p.x, "y": p.y, "r": g.radius, "charges": st.charges, "gadget": g.kind, "slot": float(slot)})
	return true

## Bombe : visée du bouton s'il a été glissé, sinon celle de l'attaque, sinon l'ennemi pertinent à
## portée. « Grappe » (amélioration, `count` > 1) : `count` bombes en éventail sur `spread` degrés.
static func _throw_bombs(game: Dictionary, g: Dictionary, aim_x: float, aim_y: float) -> void:
	var p: Dictionary = game.player
	var manual: bool = D6Js.truthy(aim_x) or D6Js.truthy(aim_y)
	var aim: Dictionary = D6Aim.compute_aim(game, aim_x if manual else p.manualAimX, aim_y if manual else p.manualAimY, g.range)
	var count: float = D6Js.nz(g.get("count"), 1.0)
	if count <= 1.0:
		_throw_bomb(game, g, aim.x, aim.y, aim.targetId)
		return
	var base: float = D6Trig.atan2(aim.y, aim.x)
	var spread: float = D6Js.nz(g.get("spread"), 0.0) * D6Data.DEG
	var i := 0.0
	while i < count:
		var ang: float = base + (i / (count - 1.0) - 0.5) * spread
		_throw_bomb(game, g, D6Trig.cos(ang), D6Trig.sin(ang), aim.targetId)
		i += 1.0

static func _throw_bomb(game: Dictionary, g: Dictionary, dir_x: float, dir_y: float, target_id) -> void:
	var p: Dictionary = game.player
	var target: Dictionary = D6KitCommon.throw_point(game, dir_x, dir_y, target_id, g.range, g.throwDist, _point)
	D6KitZones.spawn_zone(game, {
		"kind": "bombe", "phase": "flight", "x": p.x, "y": p.y, "x0": p.x, "y0": p.y, "tx": target.x, "ty": target.y, "flight": g.flight, "lift": 0.0,
		"fuse": g.fuse, "r": g.radius, "damage": g.damage, "knockback": g.knockback, "stun": g.stun, "hitstop": g.hitstop, "shake": g.shake,
	})

## Piège posé aux pieds. « Champ de pièges » (amélioration, `count` > 1) : `count` pièges en cercle
## à `ringDist` u du héros ; un point dans un mur ou dans l'eau retombe à ses pieds.
static func _lay_traps(game: Dictionary, g: Dictionary) -> void:
	var p: Dictionary = game.player
	var count: float = D6Js.nz(g.get("count"), 1.0)
	if count <= 1.0:
		_lay_trap(game, g, p.x, p.y)
		return
	var i := 0.0
	while i < count:
		var ang: float = p.facing + (i / count) * PI * 2.0
		var x: float = p.x + D6Trig.cos(ang) * g.ringDist
		var y: float = p.y + D6Trig.sin(ang) * g.ringDist
		var bad: bool = D6Physics.point_blocked(game.room, x, y, 0.0) or D6Physics.low_at(game.room, x, y, 0.0)
		_lay_trap(game, g, p.x if bad else x, p.y if bad else y)
		i += 1.0

static func _lay_trap(game: Dictionary, g: Dictionary, x: float, y: float) -> void:
	# Au-delà de maxActive pièges posés, le plus ancien se désarme.
	var traps: Array = D6KitZones.zones_of(game, "piege")
	var i := 0
	while float(i) <= float(traps.size()) - g.maxActive:
		traps[i].dead = true
		i += 1
	D6KitZones.spawn_zone(game, {
		"kind": "piege", "x": x, "y": y, "r": g.radius, "blastRadius": g.blastRadius, "armTime": g.armTime, "life": g.life, "armed": false,
		"damage": g.damage, "stun": g.stun, "knockback": g.knockback, "hitstop": g.hitstop, "shake": g.shake,
	})

## « Aspiration » (amélioration de la Nova, du Tourbillon : `pullMass`) : l'ennemi touché est tiré
## contre le héros au lieu d'être repoussé. Sans ce nombre : rien.
static func draw_in(game: Dictionary, e: Dictionary, def: Dictionary) -> void:
	if def.get("pullMass") == null or e.dead:
		return
	var p: Dictionary = game.player
	D6KitCommon.pull_toward(game, e, p.x, p.y, p.r + e.r + def.pullGap, def.pullMass)

## « Sol en feu » (amélioration de la Nova : `fireDuration`, `fireDps`) : le cercle de la nova brûle,
## au rythme du Brasier d'âmes (sa cadence et sa durée de brûlure). Sans ces nombres : rien.
static func nova_fire(game: Dictionary, g: Dictionary) -> void:
	if g.get("fireDuration") == null:
		return
	var p: Dictionary = game.player
	var fire: Dictionary = game.tuning.skills.brasier
	D6KitZones.spawn_zone(game, {
		"kind": "brasier", "x": p.x, "y": p.y, "r": g.radius, "duration": g.fireDuration, "tick": fire.tick, "tickT": 0.0,
		"burnDps": g.fireDps, "burnRefresh": fire.burnRefresh,
	})

## Cri du bourreau : étourdit (l'attaque en préparation est abandonnée) et rend vulnérable.
static func _roar(game: Dictionary, g: Dictionary) -> void:
	var p: Dictionary = game.player
	D6KitCommon.hit_circle(game, p.x, p.y, g.radius, {"kind": "gadget", "amount": g.damage, "knockback": g.knockback, "stun": g.stun, "hitstop": g.hitstop, "canCrit": false, "shake": g.shake})
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = g.radius + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) >= rr * rr:
			continue
		e.vuln = maxf(e.vuln, g.vuln)
		e.vulnMult = maxf(e.vulnMult, g.vulnMult)
	if g.get("surge") != null:
		# « Cri de guerre » (amélioration) : le héros gagne un élan passager, comme le proc « surge ».
		p.surge = maxf(p.surge, g.surge)
		p.surgeMult = maxf(p.surgeMult, g.surgeMult)
