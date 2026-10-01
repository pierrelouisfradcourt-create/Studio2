class_name D6KitCommon
extends RefCounted
## Portage de src/sim/kit_common.mjs.
## Briques communes des kits (armes à distance, compétences, gadgets, Supers autres que le kit
## d'origine) : registre des tirs et zones du héros, dégâts de zone, point de lancer, traction.
##
## Les tirs et zones du héros vivent DANS LA SALLE (game.room.kitFx) : un nouvel étage construit
## une nouvelle salle, et efface donc d'office tout ce que le héros y avait posé. Données pures ;
## le code qui les joue est choisi par `kind` (kit_shots, kit_zones).
## Aucune dépendance vers player (pas de dépendance circulaire).

const THROW_STEP := 8.0 # u : pas de recul d'un point de lancer tombé dans un mur ou un obstacle
const KNOCK_AXIS := 0.7 # recul d'un secteur : 70 % dans l'axe du coup, 30 % vers l'extérieur

## Tirs et zones du héros de la salle courante (créés à la demande).
static func kit_store(game: Dictionary) -> Dictionary:
	var room: Dictionary = game.room
	if room.get("kitFx") == null:
		room.kitFx = {"shots": [], "zones": []}
	return room.kitFx

## Ennemi vivant et ciblable d'après son id (0 = aucun). Rend null s'il n'y en a pas.
static func live_enemy(game: Dictionary, id):
	if not D6Js.truthy(id):
		return null
	for o in game.enemies:
		if o.id == id:
			return o if (not o.dead and not (o.spawnT > 0.0)) else null
	return null

## Dégâts à tous les ennemis d'un cercle (recul dirigé depuis le centre). `src` : comme
## damage_enemy, sans direction. Rend le nombre d'ennemis touchés.
static func hit_circle(game: Dictionary, x: float, y: float, r: float, src: Dictionary) -> float:
	var n := 0.0
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = r + e.r
		var d2: float = D6Geo.dist2(x, y, e.x, e.y)
		if d2 >= rr * rr:
			continue
		var l: float = maxf(1e-6, sqrt(d2))
		var hit: Dictionary = src.duplicate()
		hit.dirX = (e.x - x) / l
		hit.dirY = (e.y - y) / l
		D6Combat.damage_enemy(game, e, hit)
		n += 1.0
	return n

## Dégâts à tous les ennemis d'un secteur (comme un coup de mêlée) ; les projectiles ennemis
## balayés sont détruits (parade). `arc` en radians. Rend le nombre d'ennemis touchés.
static func hit_sector(game: Dictionary, x: float, y: float, reach: float, angle: float, arc: float, src: Dictionary) -> float:
	var dir_x: float = D6Trig.cos(angle)
	var dir_y: float = D6Trig.sin(angle)
	var n := 0.0
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		if not D6Geo.in_sector(e.x, e.y, x, y, reach, angle, arc, e.r):
			continue
		var dx: float = e.x - x
		var dy: float = e.y - y
		var l: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
		var kx: float = dir_x * KNOCK_AXIS + (dx / l) * (1.0 - KNOCK_AXIS)
		var ky: float = dir_y * KNOCK_AXIS + (dy / l) * (1.0 - KNOCK_AXIS)
		var kl: float = maxf(1e-6, sqrt(kx * kx + ky * ky))
		var hit: Dictionary = src.duplicate()
		hit.dirX = kx / kl
		hit.dirY = ky / kl
		D6Combat.damage_enemy(game, e, hit)
		n += 1.0
	var projectiles: Array = game.projectiles
	var j := 0
	while j < projectiles.size():
		var pr: Dictionary = projectiles[j]
		j += 1
		if pr.get("owner") != "enemy" or D6Js.truthy(pr.get("dead")):
			continue
		if D6Geo.in_sector(pr.x, pr.y, x, y, reach, angle, arc, pr.r):
			pr.dead = true
			game.telemetry.deflects += 1.0
			D6State.emit(game, "deflect", {"x": pr.x, "y": pr.y})
	return n

## Point d'impact d'un objet LANCÉ (pot, bombe) dans la direction (dir_x, dir_y) : sur la cible
## visée si elle est à portée, sinon à `default_dist`. Le lancer passe au-dessus des obstacles,
## mais l'objet ne retombe jamais dans un mur : on recule le long du lancer. Écrit dans `out`.
static func throw_point(game: Dictionary, dir_x: float, dir_y: float, target_id, max_range: float, default_dist: float, out: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var d: float = default_dist
	var e = live_enemy(game, target_id)
	if e != null:
		d = minf(max_range, sqrt(D6Geo.dist2(p.x, p.y, e.x, e.y)))
	while d > 0.0 and D6Physics.point_blocked(game.room, p.x + dir_x * d, p.y + dir_y * d, 0.0):
		d -= THROW_STEP
	d = maxf(0.0, d)
	out.x = p.x + dir_x * d
	out.y = p.y + dir_y * d
	return out

## Tire un ennemi vers (x, y) jusqu'à `stop_dist` de ce point (centre à centre), par son élan
## (kvx, kvy) : la friction des ennemis l'arrête pile à l'arrivée. Les ennemis plus lourds que
## `pull_mass` viennent moins loin ; un blindé résiste comme au recul ; un Gardien ne bouge pas.
static func pull_toward(game: Dictionary, e: Dictionary, x: float, y: float, stop_dist: float, pull_mass: float) -> float:
	if D6Js.truthy(e.get("dead")) or D6Js.truthy(e.get("boss")):
		return 0.0
	var t: Dictionary = game.tuning
	var dx: float = x - e.x
	var dy: float = y - e.y
	var d: float = sqrt(dx * dx + dy * dy)
	var travel: float = d - stop_dist
	if travel <= 0.0 or d < 1e-6:
		return 0.0
	# Somme géométrique de l'intégration (enemies) : déplacement total = v0 × DT / (1 − k).
	var k: float = D6Trig.exp(-t.combat.enemyFriction * D6Data.DT)
	var v0: float = (travel * (1.0 - k)) / D6Data.DT
	v0 *= minf(1.0, pull_mass / maxf(1e-6, e.mass))
	if e.get("eliteMod") == "blinde":
		v0 *= t.elite.mods.blinde.knockbackMult
	e.kvx = (dx / d) * v0
	e.kvy = (dy / d) * v0
	return v0
