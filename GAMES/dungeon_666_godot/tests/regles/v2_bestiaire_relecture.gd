extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_bestiaire_relecture.test.mjs.
## Tests issus de la relecture adversariale du lot BESTIAIRE (V2) : un test par défaut corrigé.
##
##   - un tireur (Archer, Pyromancienne) attaque encore quand le héros est derrière un obstacle ;
##   - frapper une invocation ne rapporte pas d'or (pas de ferme tant que l'invocateur vit) ;
##   - salle nettoyée : plus aucun coup ennemi en attente ne part ;
##   - une brûlure éteinte repart de zéro (la suivante brûle à sa propre intensité).
## Le champion des salles d'élite (bestiaire de l'étage) est dans v2_etages_relecture.gd.

const BIG_HP := 1e6

static func tests(h) -> void:
	h.test("tireurs : héros immobile derrière un obstacle, l'Archer et la Pyromancienne finissent par attaquer", func(): _tireurs(h))
	h.test("invocations : « Main avide » ne rapporte pas d'or sur une invocation, mais bien sur un ennemi ordinaire", func(): _invocations(h))
	h.test("salle nettoyée : les zones en attente et les projectiles ennemis en vol sont annulés", func(): _salle_nettoyee(h))
	h.test("brûlure : une fois éteinte, son intensité repart de zéro", func(): _brulure(h))

# ---------------------------------------------------------------- outillage

## Salle réelle vidée de ses vagues (obstacles gardés), héros increvable.
static func _emptied(seed_n: float, floor: float) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": floor})
	g.enemies.clear()
	g.spawns.clear()
	g.room.waves = []
	g.room.kind = "event" # la salle ne se « nettoie » pas pendant l'essai
	g.events.clear()
	g.player.maxHp = BIG_HP
	g.player.hp = BIG_HP
	return g

static func _count(evs: Array, type: String) -> int:
	var n := 0
	for ev in evs:
		if ev.type == type:
			n += 1
	return n

# ---------------------------------------------------------------- tireurs derrière un obstacle

static func _tireurs(h) -> void:
	for kind in ["archer", "pyromancer"]:
		# Disposition « lanes » (graine 77, étage 150) : héros collé sous le mur, tireur de l'autre côté.
		var g := _emptied(77.0, 150.0)
		var p: Dictionary = g.player
		var o = g.room.obstacles[1] if g.room.obstacles.size() > 1 else null
		if not h.ok(o != null, "la salle a ses obstacles"):
			continue
		p.x = (o.x0 + o.x1) / 2.0 + 60.0
		p.y = o.y1 + p.r
		var e: Dictionary = D6Enemies.create_enemy(g, kind, p.x - 100.0, o.y0 - 190.0, {"spawnT": 0.0})
		h.egal(D6Physics.line_of_sight(g.room, e.x, e.y, p.x, p.y), false, "%s : pas de ligne de vue au départ" % kind)
		var attacks := _count(h.avancer(g, h.ticks(30.0)), "enemyAttack")
		h.ok(attacks > 0, "%s : %d attaque en 30 s (il vibrait sur place sans jamais tirer)" % [kind, attacks])

# ---------------------------------------------------------------- invocations : pas de ferme

static func _invocations(h) -> void:
	var g := _emptied(5.0, 3.0)
	g.tuning.combat.critChance = 0.0
	g.player.procs.append({"on": "hit", "sources": ["melee"], "effect": "gold", "chance": 1.0, "value": 1.0})
	var summoned: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, {"spawnT": 0.0, "summoned": true})
	var ordinary: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x - 200.0, g.player.y, {"spawnT": 0.0})
	for e in [summoned, ordinary]:
		e.hp = BIG_HP
		e.maxHp = BIG_HP
	var gold0: float = g.run.gold
	for i in 20:
		D6Combat.damage_enemy(g, summoned, {"kind": "melee", "amount": 5.0, "canCrit": false})
	h.egal(g.run.gold, gold0, "invocation : aucun or")
	D6Combat.damage_enemy(g, ordinary, {"kind": "melee", "amount": 5.0, "canCrit": false})
	h.egal(g.run.gold, gold0 + 1.0, "ennemi ordinaire : la bénédiction paie")

# ---------------------------------------------------------------- salle nettoyée

static func _salle_nettoyee(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 5.0, "startFloor": 2.0})
	var p: Dictionary = g.player
	h.ok(g.room.kind == "combat" or g.room.kind == "elite")
	# Un souffle d'élite ardent sous les pieds du héros (0,7 s de télégraphe) et une flèche vers lui.
	var hz: Dictionary = D6Combat.spawn_hazard(g, {"shape": "circle", "x": p.x, "y": p.y, "r": 110.0, "delay": 0.7, "damage": 18.0, "hitsPlayer": true, "hitsEnemies": false, "kind": "fireBlast", "sourceId": 0.0})
	var arrow: Dictionary = D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 300.0, "y": p.y, "vx": -200.0, "vy": 0.0, "r": 7.0, "damage": 10.0, "range": 700.0, "sourceId": 0.0})
	# Le dernier ennemi tombe : la salle est nettoyée.
	g.room.waveIndex = float(g.room.waves.size()) - 1.0
	g.spawns.clear()
	for e in g.enemies:
		e.dead = true
	var hp0: float = p.hp
	var i := 0
	while i < 60 and not D6Js.truthy(g.room.cleared):
		D6Game.step_game(g, D6Game.empty_input())
		i += 1
	h.egal(g.room.cleared, true)
	h.egal(hz.get("done"), true, "la zone en attente est annulée")
	h.egal(arrow.get("dead"), true, "la flèche en vol est retirée")
	# (Comme le test web, les événements accumulés pendant le nettoyage ne sont pas vidés avant.)
	var evs: Array = g.events.duplicate()
	g.events.clear()
	evs.append_array(h.avancer(g, h.ticks(2.0)))
	h.egal(_count(evs, "playerHurt"), 0, "plus aucun coup après « salle nettoyée »")
	h.egal(p.hp, hp0)

# ---------------------------------------------------------------- brûlure

static func _brulure(h) -> void:
	var g := _emptied(5.0, 3.0)
	var e: Dictionary = D6Enemies.create_enemy(g, "brute", g.player.x + 300.0, g.player.y, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.hp = BIG_HP
	e.maxHp = BIG_HP
	e.burn = 0.5
	e.burnDps = 40.0
	h.avancer(g, h.ticks(1.0))
	h.ok(e.burn <= 0.0, "la brûlure forte est éteinte")
	h.egal(e.burnDps, 0.0, "son intensité ne reste pas en mémoire")
	# Une brûlure faible posée ensuite (même règle que combat.mjs : le max des deux) brûle à 6/s.
	e.burn = 2.0
	e.burnDps = maxf(e.burnDps, 6.0)
	var hp0: float = e.hp
	h.avancer(g, h.ticks(2.2))
	var lost: float = hp0 - e.hp
	# 12 PV nominaux ; chaque tick de 0,25 s (1,5 PV) est arrondi à l'entier : 16 au plus.
	h.ok(lost >= 9.0 and lost <= 20.0, "2 s à 6/s : %s PV perdus (40/s en aurait pris ~80)" % D6Js.num_str(lost))
