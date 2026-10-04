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

static var _point := {"x": 0.0, "y": 0.0}

static func use_kit_gadget(game: Dictionary, g: Dictionary, slot: int, aim_x: float = 0.0, aim_y: float = 0.0) -> bool:
	var p: Dictionary = game.player
	var st: Dictionary = p.slots[slot]
	st.charges -= 1.0
	if D6Js.truthy(g.get("iframes")):
		p.iframes = maxf(p.iframes, g.iframes)
	match g.kind:
		"bombe":
			# Visée : celle du bouton s'il a été glissé, sinon celle de l'attaque, sinon l'ennemi pertinent à portée.
			var manual: bool = D6Js.truthy(aim_x) or D6Js.truthy(aim_y)
			var aim: Dictionary = D6Aim.compute_aim(game, aim_x if manual else p.manualAimX, aim_y if manual else p.manualAimY, g.range)
			var target: Dictionary = D6KitCommon.throw_point(game, aim.x, aim.y, aim.targetId, g.range, g.throwDist, _point)
			D6KitZones.spawn_zone(game, {
				"kind": "bombe", "phase": "flight", "x": p.x, "y": p.y, "x0": p.x, "y0": p.y, "tx": target.x, "ty": target.y, "flight": g.flight, "lift": 0.0,
				"fuse": g.fuse, "r": g.radius, "damage": g.damage, "knockback": g.knockback, "stun": g.stun, "hitstop": g.hitstop, "shake": g.shake,
			})
		"piege":
			# Au-delà de maxActive pièges posés, le plus ancien se désarme.
			var traps: Array = D6KitZones.zones_of(game, "piege")
			var i := 0
			while float(i) <= float(traps.size()) - g.maxActive:
				traps[i].dead = true
				i += 1
			D6KitZones.spawn_zone(game, {
				"kind": "piege", "x": p.x, "y": p.y, "r": g.radius, "blastRadius": g.blastRadius, "armTime": g.armTime, "life": g.life, "armed": false,
				"damage": g.damage, "stun": g.stun, "knockback": g.knockback, "hitstop": g.hitstop, "shake": g.shake,
			})
		"cri":
			_roar(game, g)
		"totem":
			D6KitZones.spawn_zone(game, {
				"kind": "totem", "x": p.x, "y": p.y, "r": g.radius, "life": g.life, "pulse": g.pulse, "pulseT": 0.0, "damage": g.damage,
				"chill": g.chill, "chillMult": g.chillMult,
			})
	game.telemetry.gadgetUses += 1.0
	D6State.emit(game, "gadget", {"x": p.x, "y": p.y, "r": g.radius, "charges": st.charges, "gadget": g.kind, "slot": float(slot)})
	return true

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
