class_name D6KitZones
extends RefCounted
## Portage de src/sim/kit_zones.mjs.
## ZONES DU HÉROS — objets posés ou lancés qui agissent dans la durée : pot du Brasier d'âmes
## (vol, puis sol qui brûle), Bombe de soufre (vol, mèche, explosion), Piège à mâchoires
## (armement, déclenchement), Totem de givre (impulsions). Elles ne blessent JAMAIS le héros :
## ce sont ses outils (dessinés dans les teintes froides du héros, jamais en rouge).
##
## Elles vivent dans game.room.kitFx.zones (kit_common) ; chaque zone copie ses chiffres à
## la pose (un réglage modifié ensuite ne change pas un objet déjà posé).
##
## zone : {id, kind, x, y, r, t, dead, ...} — kind : pot | brasier | bombe | piege | totem | faille
## (`faille` : sim/kit_neuves.gd ; un brasier marqué `trail` est une braise du Sillage).
## Les objets lancés (pot, bombe) portent x0, y0, tx, ty, flight et leur hauteur `lift` (0..1).

const Neuves := preload("res://sim/kit_neuves.gd")

static func spawn_zone(game: Dictionary, z: Dictionary) -> Dictionary:
	var zone := {"id": D6State.new_id(game), "t": 0.0, "dead": false}
	zone.merge(z, true)
	D6KitCommon.kit_store(game).zones.append(zone)
	return zone

## Zones actives d'un type (pièges posés…), dans l'ordre de pose.
static func zones_of(game: Dictionary, kind: String) -> Array:
	var store = game.room.get("kitFx")
	if store == null:
		return []
	return store.zones.filter(func(z): return z.kind == kind and not z.dead)

static func update_zones(game: Dictionary, dt: float) -> void:
	var store = game.room.get("kitFx")
	if store == null or store.zones.size() == 0:
		return
	var zones: Array = store.zones
	var i := 0
	while i < zones.size():
		var z: Dictionary = zones[i]
		i += 1
		if z.dead:
			continue
		z.t += dt
		# Table ZONES du JavaScript : le code est choisi par `kind` (un kind inconnu ne fait rien).
		match z.kind:
			"pot":
				_pot(game, z)
			"brasier":
				_brasier(game, z, dt)
			"bombe":
				_bombe(game, z)
			"piege":
				_piege(game, z)
			"totem":
				_totem(game, z, dt)
			"faille":
				Neuves.zone(game, z) # compétence neuve (étape 4) : réplique, fissure ouverte
	D6Projectiles.compact(store.zones)

## Objet lancé en cloche : rend true à l'atterrissage (position posée sur la cible).
static func _fly(z: Dictionary) -> bool:
	var k: float = minf(1.0, z.t / maxf(1e-6, z.flight))
	z.x = z.x0 + (z.tx - z.x0) * k
	z.y = z.y0 + (z.ty - z.y0) * k
	z.lift = 4.0 * k * (1.0 - k) # hauteur de la cloche (rendu) : 0 au départ et à l'arrivée
	return k >= 1.0

## Pot du Brasier d'âmes : impact à l'atterrissage, puis il devient un sol qui brûle.
static func _pot(game: Dictionary, z: Dictionary) -> void:
	if not _fly(z):
		return
	D6KitCommon.hit_circle(game, z.x, z.y, z.r, {"kind": "skill", "amount": z.damage, "knockback": z.knockback, "hitstop": z.hitstop, "canCrit": true, "stun": D6Js.nz(z.get("stun"), 0.0)})
	D6State.emit(game, "explode", {"x": z.x, "y": z.y, "r": z.r, "hero": true, "kind": "brasier"})
	if z.duration <= 0.0:
		z.dead = true # « Pot explosif » (amélioration) : aucune flamme ne reste
		return
	z.kind = "brasier"
	z.t = 0.0
	z.tickT = 0.0

## Sol qui brûle : rafraîchit la brûlure (statut des ennemis) de ceux qui s'y tiennent.
static func _brasier(game: Dictionary, z: Dictionary, dt: float) -> void:
	if z.t >= z.duration:
		z.dead = true
		return
	z.tickT -= dt
	if z.tickT > 0.0:
		return
	z.tickT += z.tick
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = z.r + e.r
		if D6Geo.dist2(z.x, z.y, e.x, e.y) >= rr * rr:
			continue
		e.burn = maxf(e.burn, z.burnRefresh)
		e.burnDps = maxf(e.burnDps, z.burnDps)
		if D6Js.nz(z.get("chill"), 0.0) > 0.0:
			# « Poix » (amélioration du Brasier) : les flammes ralentissent aussi.
			e.chill = maxf(e.chill, z.chill)
			var cur: float = e.chillMult if D6Js.truthy(e.get("chillMult")) else 1.0
			e.chillMult = minf(cur, maxf(game.tuning.combat.minChillMult, z.chillMult))

## Bombe : vol, mèche, explosion (étourdit, efface les projectiles ennemis du souffle).
static func _bombe(game: Dictionary, z: Dictionary) -> void:
	if z.get("phase") == "flight":
		if not _fly(z):
			return
		z.phase = "fuse"
		z.t = 0.0
		return
	if z.t < z.fuse:
		return
	D6KitCommon.hit_circle(game, z.x, z.y, z.r, {"kind": "gadget", "amount": z.damage, "knockback": z.knockback, "stun": z.stun, "hitstop": z.hitstop, "canCrit": false, "shake": z.shake})
	D6Projectiles.destroy_enemy_projectiles_in_circle(game, z.x, z.y, z.r)
	D6State.emit(game, "explode", {"x": z.x, "y": z.y, "r": z.r, "hero": true, "kind": "bombe"})
	z.dead = true
	if z.get("fireDuration") != null:
		# « Poix ardente » : le cercle du souffle brûle, au rythme du Brasier d'âmes (comme la Nova en feu).
		var fire: Dictionary = game.tuning.skills.brasier
		spawn_zone(game, {"kind": "brasier", "x": z.x, "y": z.y, "r": z.r, "duration": z.fireDuration, "tick": fire.tick, "tickT": 0.0, "burnDps": z.fireDps, "burnRefresh": fire.burnRefresh})

## Piège : s'arme, puis se referme sur le premier ennemi qui entre (immobilise : étourdi).
static func _piege(game: Dictionary, z: Dictionary) -> void:
	if z.t >= z.life:
		z.dead = true
		return
	if z.t < z.armTime:
		return
	z.armed = true
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = z.r + e.r
		if D6Geo.dist2(z.x, z.y, e.x, e.y) >= rr * rr:
			continue
		D6KitCommon.hit_circle(game, z.x, z.y, z.blastRadius, {"kind": "gadget", "amount": z.damage, "knockback": z.knockback, "stun": z.stun, "hitstop": z.hitstop, "canCrit": false, "shake": z.shake})
		D6State.emit(game, "explode", {"x": z.x, "y": z.y, "r": z.blastRadius, "hero": true, "kind": "piege"})
		z.dead = true
		return

## Totem : impulsions qui blessent et ralentissent tout ce qui est à portée.
static func _totem(game: Dictionary, z: Dictionary, dt: float) -> void:
	if z.t >= z.life:
		z.dead = true
		return
	z.pulseT -= dt
	if z.pulseT > 0.0:
		return
	z.pulseT += z.pulse
	var min_chill: float = game.tuning.combat.minChillMult
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = z.r + e.r
		if D6Geo.dist2(z.x, z.y, e.x, e.y) >= rr * rr:
			continue
		D6Combat.damage_enemy(game, e, {"kind": "gadget", "amount": z.damage, "dirX": 0.0, "dirY": 0.0, "canCrit": false})
		if e.dead:
			continue
		e.chill = maxf(e.chill, z.chill)
		var cur: float = e.chillMult if D6Js.truthy(e.get("chillMult")) else 1.0
		e.chillMult = minf(cur, maxf(min_chill, z.chillMult))
	if D6Js.truthy(z.get("ward")):
		D6Projectiles.destroy_enemy_projectiles_in_circle(game, z.x, z.y, z.r) # « Totem gardien » (amélioration)
	D6State.emit(game, "kitPulse", {"x": z.x, "y": z.y, "r": z.r, "kind": "totem"})
