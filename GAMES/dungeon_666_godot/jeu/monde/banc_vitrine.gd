extends RefCounted
## Vitrine du banc du Monde : pose dans une partie FIGÉE un échantillon de ce que le Monde sait
## dessiner, par les constructeurs de la simulation. Outil d'essai seulement (jeu/monde/banc.gd,
## D666_VITRINE) : jamais appelé par le jeu.
##   D666_VITRINE=dangers                 zones, télégraphes, flaque, invocations, tirs ennemis
##   D666_VITRINE=heros                   tirs et zones des kits du héros, ramassables
##   D666_VITRINE=boon|loot|shop|event|treasure|rest   salle nettoyée : cet objet et des portes

const PORTES_A := [{"reward": "boon", "family": "colere"}, {"reward": "loot"}, {"reward": "gold"}, {"reward": "heal"}, {"reward": "town"}]
const PORTES_B := [{"reward": "elite"}, {"reward": "shop"}, {"reward": "event"}, {"reward": "treasure"}, {"reward": "rest"}, {"reward": "boss"}]

static func poser(g: Dictionary, mode: String) -> void:
	g.spawns.clear()
	var c := Vector2(g.room.w / 2.0, g.room.h - 300.0)
	match mode:
		"dangers":
			_placer_heros(g, c + Vector2(0, 60))
			_dangers(g, c)
		"heros":
			_placer_heros(g, c + Vector2(0, 60))
			_heros(g, c)
		_:
			_placer_heros(g, Vector2(g.room.w / 2.0 + 90.0, 230.0))
			_sortie(g, mode)

static func _placer_heros(g: Dictionary, p: Vector2) -> void:
	g.player.x = p.x
	g.player.y = p.y
	g.player.facing = -PI / 2.0

static func _zone(g: Dictionary, h: Dictionary) -> void:
	var z := {"id": D6State.new_id(g), "kind": "essai", "inner": 0.0, "t": 0.0, "sourceId": 0.0, "hitsPlayer": true, "hitsEnemies": false, "done": false}
	z.merge(h, true)
	g.hazards.append(z)

static func _dangers(g: Dictionary, c: Vector2) -> void:
	_zone(g, {"shape": "circle", "x": c.x - 300.0, "y": c.y - 60.0, "r": 80.0, "delay": 1.0, "t": 0.55})
	_zone(g, {"shape": "ring", "x": c.x + 290.0, "y": c.y - 50.0, "r": 110.0, "inner": 55.0, "delay": 1.0, "t": 0.6})
	_zone(g, {"shape": "line", "x": c.x - 380.0, "y": c.y + 170.0, "angle": -0.25, "length": 300.0, "width": 44.0, "delay": 1.0, "t": 0.7})
	_zone(g, {"shape": "circle", "x": c.x + 60.0, "y": c.y + 150.0, "r": 70.0, "delay": 0.5, "t": 0.5, "burning": true, "burnT": 1.4, "linger": 4.0, "tickT": 0.0})
	var cone: Dictionary = D6Enemies.create_enemy(g, "imp", c.x - 120.0, c.y - 120.0, {})
	cone.tele = {"shape": "cone", "angle": 0.6, "range": 130.0, "arc": 0.9, "progress": 0.6}
	var ligne: Dictionary = D6Enemies.create_enemy(g, "archer", c.x + 330.0, c.y + 130.0, {})
	ligne.tele = {"shape": "line", "angle": PI + 0.3, "length": 320.0, "width": 16.0, "progress": 0.85}
	var cercle: Dictionary = D6Enemies.create_enemy(g, "exploder", c.x + 110.0, c.y - 100.0, {})
	cercle.tele = {"shape": "circle", "r": 75.0, "progress": 0.3}
	var chant: Dictionary = D6Enemies.create_enemy(g, "imp", c.x - 230.0, c.y + 80.0, {})
	chant.tele = {"shape": "circle", "r": 70.0, "progress": 0.5, "harmless": true}
	for e in [cone, ligne, cercle, chant]:
		e.spawnT = 0.0
	D6Spawns.queue_spawn(g, "imp", c.x - 40.0, c.y - 190.0, {"warn": 1.0}).t = 0.3
	D6Spawns.queue_spawn(g, "brute", c.x + 40.0, c.y - 190.0, {"warn": 1.0, "elite": "ardent"}).t = 0.7
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": c.x + 180.0, "y": c.y + 40.0, "vx": -300.0, "vy": 60.0, "r": 6.0, "damage": 1.0})
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "bossOrb", "x": c.x - 170.0, "y": c.y + 10.0, "vx": 200.0, "vy": 0.0, "r": 9.0, "damage": 1.0})
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "bossOrb", "x": c.x - 140.0, "y": c.y + 40.0, "vx": 200.0, "vy": 0.0, "r": 9.0, "damage": 1.0})

static func _heros(g: Dictionary, c: Vector2) -> void:
	var x := c.x - 330.0
	for genre in ["arrow", "bolt", "thorn", "hook", "star"]:
		D6KitShots.spawn_shot(g, {"kind": genre, "x": x, "y": c.y - 150.0, "vx": 300.0, "vy": -200.0, "r": 5.0, "range": 900.0, "damage": 1.0, "source": "melee", "heavy": genre == "bolt"})
		x += 70.0
	D6Projectiles.spawn_projectile(g, {"owner": "player", "kind": "lance", "x": c.x + 80.0, "y": c.y - 170.0, "vx": 500.0, "vy": -120.0, "r": 8.0, "damage": 1.0})
	D6KitZones.spawn_zone(g, {"kind": "pot", "x": c.x - 250.0, "y": c.y - 30.0, "x0": c.x, "y0": c.y, "tx": c.x - 330.0, "ty": c.y - 40.0, "flight": 0.5, "lift": 0.9, "r": 70.0})
	D6KitZones.spawn_zone(g, {"kind": "brasier", "x": c.x - 150.0, "y": c.y + 130.0, "r": 80.0, "duration": 4.0, "t": 1.0, "tick": 0.5, "tickT": 0.0})
	D6KitZones.spawn_zone(g, {"kind": "bombe", "phase": "fuse", "x": c.x + 130.0, "y": c.y + 120.0, "r": 90.0, "fuse": 1.0, "t": 0.6})
	D6KitZones.spawn_zone(g, {"kind": "bombe", "phase": "flight", "x": c.x + 250.0, "y": c.y - 80.0, "x0": c.x, "y0": c.y, "tx": c.x + 330.0, "ty": c.y - 90.0, "flight": 0.5, "lift": 0.8, "r": 90.0})
	D6KitZones.spawn_zone(g, {"kind": "piege", "x": c.x + 330.0, "y": c.y + 110.0, "r": 46.0, "armTime": 0.5, "t": 1.0, "life": 20.0})
	D6KitZones.spawn_zone(g, {"kind": "piege", "x": c.x + 250.0, "y": c.y + 190.0, "r": 46.0, "armTime": 0.5, "t": 0.1, "life": 20.0})
	D6KitZones.spawn_zone(g, {"kind": "totem", "x": c.x - 340.0, "y": c.y + 140.0, "r": 90.0, "life": 8.0, "t": 1.0, "pulse": 1.0, "pulseT": 0.5})
	_zone(g, {"shape": "circle", "x": c.x + 170.0, "y": c.y - 60.0, "r": 60.0, "delay": 0.5, "t": 0.3, "hitsPlayer": false, "hitsEnemies": true})
	for i in 5:
		g.pickups.append({"id": D6State.new_id(g), "kind": "gold", "x": c.x - 60.0 + 26.0 * float(i), "y": c.y - 40.0 + 9.0 * float(i % 2), "vx": 0.0, "vy": 0.0, "r": 8.0, "value": 1.0, "age": 0.0})
	g.pickups.append({"id": D6State.new_id(g), "kind": "heal", "x": c.x + 20.0, "y": c.y - 90.0, "vx": 0.0, "vy": 0.0, "r": 12.0, "value": 1.0, "age": 0.0})

## Salle nettoyée : l'objet d'interaction `genre` au centre, des portes ouvertes, une fermée.
static func _sortie(g: Dictionary, genre: String) -> void:
	g.enemies.clear()
	g.room.cleared = true
	D6Room.make_doors(g, PORTES_A if genre in ["boon", "shop", "treasure"] else PORTES_B)
	g.room.doors[1].open = false
	var p := Vector2(g.room.w / 2.0, 230.0)
	var objet := {"kind": genre, "x": p.x, "y": p.y, "r": 30.0, "used": false}
	if genre == "boon":
		objet.family = "luxure"
	elif genre == "loot":
		objet.item = D6Loot.generate_item(g, {"rarity": "legendaire"})
	g.room.interact = objet
