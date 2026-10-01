class_name D6Enemies
extends RefCounted
## Portage de src/sim/enemies.mjs.
## Ennemis : création, IA par archétype, statuts, knockback, collisions.
##
## Règle de lisibilité : AUCUN dégât de contact. Tout coup ennemi passe par un télégraphe
## (e.tele ou une zone de danger) d'une durée >= au seuil de réaction, et un nombre limité
## d'ennemis de mêlée attaque en même temps (jetons d'attaque).

const BURN_TICK := 0.25

# Table des IA par archétype (const AI = {...}), construite une fois.
static var _ai_table: Dictionary = {}

static func create_enemy(game: Dictionary, kind: String, x: float, y: float, opts = null) -> Dictionary:
	if opts == null:
		opts = {}
	var t: Dictionary = game.tuning
	var is_boss: bool = D6Js.truthy(opts.get("boss"))
	var def: Dictionary = t.boss[kind] if is_boss else t.enemies[kind]
	var scale: Dictionary = D6Floors.floor_scaling(t, game.run.floor)
	var elite = opts.get("elite") # opts.elite ?? null
	var is_elite: bool = D6Js.truthy(elite)
	var size_mult: float = t.elite.sizeMult if is_elite else 1.0
	var hp: float = D6Js.jround(def.hp * scale.hp * (t.elite.hpMult if is_elite else 1.0))
	# Effets de bord du littéral JavaScript, dans l'ordre du texte : id, puis trois tirages dans
	# game.rng.ai (cooldown, strafe, flank).
	var id = D6State.new_id(game)
	var cooldown: float = 0.4 + D6Rng.rand(game.rng.ai) * 0.8 # désynchronise les premières attaques
	var strafe: float = -1.0 if D6Rng.rand(game.rng.ai) < 0.5 else 1.0
	var flank: float = D6Rng.rand(game.rng.ai) * PI * 2.0
	var e: Dictionary = {
		"id": id,
		"kind": kind,
		"boss": is_boss,
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"kvx": 0.0,
		"kvy": 0.0,
		"r": def.radius * size_mult,
		"hp": hp,
		"maxHp": hp,
		"mass": def.mass * (1.5 if is_elite else 1.0),
		"dmgScale": scale.damage * (t.elite.damageMult if is_elite else 1.0),
		"eliteMod": elite,
		"state": "chase",
		"stateTime": 0.0,
		"cooldown": cooldown,
	}
	# Suite du même littéral (les clés gardent l'ordre du JavaScript).
	e.merge(_enemy_rest(game, opts, strafe, flank))
	game.enemies.append(e)
	D6State.emit(game, "spawn", {"id": e.id, "x": x, "y": y, "enemy": kind, "elite": is_elite, "boss": is_boss})
	return e

# Seconde moitié du littéral de createEnemy (de `dirX` à `patternT`), sans effet de bord.
static func _enemy_rest(game: Dictionary, opts: Dictionary, strafe: float, flank: float) -> Dictionary:
	return {
		"dirX": 0.0,
		"dirY": 1.0,
		"tele": null,
		"flash": 0.0,
		"stun": 0.0,
		"guard": 0.0, # garde restante après un étourdissement (combat.stunGuard) : pas de ré-étourdissement à l'arme
		"burn": 0.0,
		"burnDps": 0.0,
		"burnAcc": 0.0,
		"chill": 0.0,
		"chillMult": 1.0,
		"vuln": 0.0,
		"vulnMult": 0.0,
		"spawnT": D6Js.nz(opts.get("spawnT"), 0.25),
		"bornAt": game.time,
		"dead": false,
		"strafe": strafe,
		"flank": flank,
		"hitPlayer": false,
		"atkId": 0.0,
		"summoned": D6Js.truthy(opts.get("summoned")),
		"lastHitAt": -1.0,
		"freeze": 0.0, # gel d'impact LOCAL restant (D8) : l'ennemi touché se fige, le reste continue
		# État propre au boss (patterns), ignoré par les autres.
		"phase": 1.0,
		"pattern": null,
		"patternStep": 0.0,
		"patternT": 0.0,
	}

static func update_enemies(game: Dictionary, dt: float) -> void:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	# for (const e of game.enemies) : voit les ennemis ajoutés pendant la boucle.
	var list: Array = game.enemies
	var i := 0
	while i < list.size():
		_update_enemy(game, list[i], dt, t, p)
		i += 1
	_separate(game)
	# La séparation pousse sans regarder les murs : on repasse la collision (jamais dans un
	# obstacle, jamais à travers un mur fin).
	list = game.enemies
	i = 0
	while i < list.size():
		var e: Dictionary = list[i]
		if not e.dead:
			D6Physics.move_circle(game.room, e, 0.0, 0.0)
		i += 1

# Corps de la boucle de updateEnemies (un `return` ici vaut le `continue` du JavaScript).
static func _update_enemy(game: Dictionary, e: Dictionary, dt: float, t: Dictionary, p: Dictionary) -> void:
	if e.dead:
		return
	if e.freeze > 0.0:
		# Gel LOCAL : figé dans la pose d'impact ; son recul part au dégel (élan conservé).
		e.freeze = maxf(0.0, e.freeze - dt)
		return
	e.stateTime += dt
	e.flash = maxf(0.0, e.flash - dt)
	if e.spawnT > 0.0:
		e.spawnT -= dt
		return
	_tick_statuses(game, e, dt)
	if e.dead:
		return
	e.cooldown = maxf(0.0, e.cooldown - dt)
	e.vx = 0.0
	e.vy = 0.0
	# Champions V2 (bouclier, invocateur, vampirique) : foe_elites.
	if D6Js.truthy(e.eliteMod) and p.state != "dead":
		D6FoeElites.update_elite_mod(game, e, dt)
	if e.stun > 0.0:
		e.stun -= dt
		e.tele = null
		if e.stun <= 0.0:
			D6AiCommon.set_state(e, "chase")
			e.cooldown = maxf(e.cooldown, 0.3)
			e.guard = t.combat.stunGuard
	elif p.state != "dead":
		e.guard = maxf(0.0, e.guard - dt)
		if e.boss:
			D6Boss.update_boss(game, e, dt)
		else:
			var hp0: float = p.hp
			_ai()[e.kind].call(game, e, t.enemies[e.kind], dt)
			if D6Js.truthy(e.eliteMod) and p.hp < hp0:
				D6FoeElites.foe_dealt(game, e, hp0 - p.hp) # coup direct qui a porté
	_integrate(game, e, dt)

static func _tick_statuses(game: Dictionary, e: Dictionary, dt: float) -> void:
	if e.chill > 0.0:
		e.chill -= dt
	else:
		e.chillMult = 1.0
	if e.vuln > 0.0:
		e.vuln -= dt
	else:
		e.vulnMult = 0.0
	if e.burn <= 0.0:
		e.burnDps = 0.0 # éteinte : la suivante brûle à sa propre intensité
	if e.burn > 0.0:
		e.burn -= dt
		e.burnAcc += e.burnDps * dt
		if e.burnAcc >= e.burnDps * BURN_TICK or e.burn <= 0.0:
			var amount: float = e.burnAcc
			e.burnAcc = 0.0
			if amount >= 0.5:
				D6Combat.damage_enemy(game, e, {"kind": "burn", "amount": amount, "canCrit": false})

static func _integrate(game: Dictionary, e: Dictionary, dt: float) -> void:
	var t: Dictionary = game.tuning
	var ws: Dictionary = t.wallSlam
	var k: float = D6Trig.exp(-t.combat.enemyFriction * dt)
	var k_speed: float = sqrt(e.kvx * e.kvx + e.kvy * e.kvy)
	var res: Dictionary = D6Physics.move_circle(game.room, e, (e.vx + e.kvx) * dt, (e.vy + e.kvy) * dt)
	if res.hitWall:
		if k_speed > ws.minSpeed and not e.boss:
			# Projeté contre un mur : dégâts bonus, étourdissement, gel d'impact — le knockback
			# devient une arme de positionnement.
			e.kvx = 0.0
			e.kvy = 0.0
			game.telemetry.wallSlams += 1.0
			D6State.emit(game, "wallSlam", {"id": e.id, "x": e.x, "y": e.y})
			D6Combat.damage_enemy(game, e, {"kind": "wall", "amount": ws.damage, "stun": ws.stun, "hitstop": ws.hitstop, "canCrit": false})
		else:
			# Glissement le long du mur : on retire la composante normale du knockback.
			var vn: float = e.kvx * res.nx + e.kvy * res.ny
			if vn < 0.0:
				e.kvx -= vn * res.nx
				e.kvy -= vn * res.ny
	e.kvx *= k
	e.kvy *= k

static func _separate(game: Dictionary) -> void:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var list: Array = game.enemies
	var i := 0
	while i < list.size():
		var a: Dictionary = list[i]
		i += 1
		if a.dead:
			continue
		var j := i # i est déjà passé à l'indice suivant : j = i + 1 du JavaScript
		while j < list.size():
			var b: Dictionary = list[j]
			j += 1
			if b.dead:
				continue
			var dx: float = b.x - a.x
			var dy: float = b.y - a.y
			var rr: float = a.r + b.r
			var d2: float = dx * dx + dy * dy
			if d2 >= rr * rr or d2 < 1e-9:
				continue
			var d: float = sqrt(d2)
			var push: float = ((rr - d) / d) * t.combat.enemySeparation
			var wa: float = b.mass / (a.mass + b.mass)
			var wb: float = a.mass / (a.mass + b.mass)
			a.x -= dx * push * wa
			a.y -= dy * push * wa
			b.x += dx * push * wb
			b.y += dy * push * wb
		# Le héros est « infiniment lourd » : il repousse les ennemis, jamais l'inverse
		# (déplacement net garanti). Pendant un dash, on traverse.
		if p.state != "dash" and p.state != "dead":
			var pdx: float = a.x - p.x
			var pdy: float = a.y - p.y
			var prr: float = a.r + p.r
			var pd2: float = pdx * pdx + pdy * pdy
			if pd2 < prr * prr and pd2 > 1e-9:
				var pd: float = sqrt(pd2)
				a.x = p.x + (pdx / pd) * prr
				a.y = p.y + (pdy / pd) * prr

# ---------------------------------------------------------------- table des IA

## const AI = { imp, archer, brute, charger, exploder } + archétypes ajoutés (un fichier chacun :
## sim/foe_<archétype>.gd), branchés dans la même table ; ils s'inscrivent au passage dans
## MELEE_KINDS / SHOOTER_KINDS (D6AiCommon). Chaque entrée : Callable(game, e, def, dt).
static func _ai() -> Dictionary:
	if _ai_table.is_empty():
		_ai_table = {
			"imp": _imp,
			"archer": _archer,
			"brute": _brute,
			"charger": _charger,
			"exploder": _exploder,
		}
		for f in D6Foes.extra_foes():
			_ai_table[f.kind] = f.ai
			if D6Js.truthy(f.get("melee")) and not D6AiCommon.melee_kinds().has(f.kind):
				D6AiCommon.melee_kinds().append(f.kind)
			if D6Js.truthy(f.get("shooter")) and not D6AiCommon.shooter_kinds().has(f.kind):
				D6AiCommon.shooter_kinds().append(f.kind)
	return _ai_table

# Fin de récupération commune à imp, brute et charger : retour en chase, recharge fixe.
static func _recover(e: Dictionary, def: Dictionary) -> void:
	if e.stateTime >= def.recover:
		D6AiCommon.set_state(e, "chase")
		e.cooldown = def.cooldown

# ---------------------------------------------------------------- imp

static func _imp(game: Dictionary, e: Dictionary, def: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	var windup := D6AiCommon.windup_of(game, e, def.windup)
	match e.state:
		"chase":
			_imp_chase(game, e, def, dt, p, tp)
		"windup":
			_imp_windup(game, e, def, windup)
		"strike":
			_imp_strike(game, e, def, p)
		"recover":
			_recover(e, def)
		_:
			D6AiCommon.set_state(e, "chase")

static func _imp_chase(game: Dictionary, e: Dictionary, def: Dictionary, dt: float, p: Dictionary, tp: Dictionary) -> void:
	var reach: float = def.attackRange + p.r
	var can_strike: bool = e.cooldown <= 0.0 and D6AiCommon.active_attackers(game) < game.tuning.combat.maxAttackers
	if tp.d < reach and can_strike:
		D6AiCommon.set_state(e, "windup")
		e.dirX = tp.dx
		e.dirY = tp.dy
		e.hitPlayer = false
		e.atkId = D6State.new_id(game)
		return
	# Sans jeton (ou en recharge) : on encercle à distance au lieu de s'empiler sur le héros.
	# Avec le droit de frapper, on fonce : sinon l'anneau (85 u) restait hors de portée (68 u)
	# et un diablotin n'attaquait plus jamais un héros immobile.
	var ring: float = reach * 1.25 if (not can_strike and tp.d < reach * 1.6) else 0.0
	var tx: float = p.x + D6Trig.cos(e.flank) * ring
	var ty: float = p.y + D6Trig.sin(e.flank) * ring
	D6AiCommon.steer(game, e, tx, ty, D6AiCommon.speed_of(game, e, def))
	e.flank += e.strafe * dt * 0.6

static func _imp_windup(game: Dictionary, e: Dictionary, def: Dictionary, windup: float) -> void:
	D6AiCommon.track_until_lock(game, e, 0.7, windup)
	e.tele = {"shape": "cone", "angle": D6Trig.atan2(e.dirY, e.dirX), "range": def.strikeSpeed * def.strikeTime + e.r + 14.0, "arc": 0.9, "progress": e.stateTime / windup}
	if e.stateTime >= windup:
		D6AiCommon.set_state(e, "strike")
		e.tele = null
		D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})

static func _imp_strike(game: Dictionary, e: Dictionary, def: Dictionary, p: Dictionary) -> void:
	e.vx = e.dirX * def.strikeSpeed
	e.vy = e.dirY * def.strikeSpeed
	var rr: float = e.r + p.r + 8.0
	if not e.hitPlayer and D6Geo.dist2(e.x, e.y, p.x, p.y) < rr * rr:
		e.hitPlayer = true
		D6Combat.damage_player(game, def.damage * e.dmgScale, {"kind": "imp", "id": e.atkId, "x": e.x, "y": e.y})
	if e.stateTime >= def.strikeTime:
		D6AiCommon.set_state(e, "recover")

# ---------------------------------------------------------------- archer

static func _archer(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	var windup := D6AiCommon.windup_of(game, e, def.windup)
	var sees: bool = D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y)
	match e.state:
		"chase":
			_archer_chase(game, e, def, p, tp, sees)
		"windup":
			_archer_windup(game, e, def, windup)
		"recover":
			if e.stateTime >= def.recover:
				D6AiCommon.set_state(e, "chase")
				e.cooldown = def.cooldown * D6Rng.rand_range(game.rng.ai, 0.85, 1.25)
		_:
			D6AiCommon.set_state(e, "chase")

static func _archer_chase(game: Dictionary, e: Dictionary, def: Dictionary, p: Dictionary, tp: Dictionary, sees: bool) -> void:
	var speed := D6AiCommon.speed_of(game, e, def)
	if e.cooldown <= 0.0 and sees and tp.d < def.projRange * 0.9 and D6AiCommon.active_shooters(game) < game.tuning.combat.maxShooters:
		D6AiCommon.set_state(e, "windup")
		e.dirX = tp.dx
		e.dirY = tp.dy
		return
	if tp.d < def.fleeDist and sees: # on ne fuit que ce qu'on voit (ai_common.keepDistance)
		e.vx = -tp.dx * speed
		e.vy = -tp.dy * speed
	elif tp.d > def.preferredDist + 60.0 or not sees:
		D6AiCommon.steer(game, e, p.x, p.y, speed)
	else:
		# Strafe perpendiculaire, change de sens de temps en temps.
		e.vx = -tp.dy * speed * 0.7 * e.strafe
		e.vy = tp.dx * speed * 0.7 * e.strafe
		if D6Rng.rand(game.rng.ai) < 0.01:
			e.strafe = -e.strafe

static func _archer_windup(game: Dictionary, e: Dictionary, def: Dictionary, windup: float) -> void:
	D6AiCommon.track_until_lock(game, e, def.lockAt, windup)
	e.tele = {"shape": "line", "angle": D6Trig.atan2(e.dirY, e.dirX), "length": def.teleLength, "width": def.projRadius * 2.0 + 4.0, "progress": e.stateTime / windup}
	if e.stateTime >= windup:
		e.tele = null
		D6Projectiles.spawn_projectile(game, {
			"owner": "enemy", "kind": "arrow",
			"x": e.x + e.dirX * (e.r + 4.0), "y": e.y + e.dirY * (e.r + 4.0),
			"vx": e.dirX * def.projSpeed, "vy": e.dirY * def.projSpeed,
			"r": def.projRadius, "damage": def.damage * e.dmgScale, "range": def.projRange, "sourceId": e.id,
		})
		D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})
		D6AiCommon.set_state(e, "recover")

# ---------------------------------------------------------------- brute

static func _brute(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	var windup := D6AiCommon.windup_of(game, e, def.windup)
	match e.state:
		"chase":
			if tp.d < def.attackRange * 0.85 + p.r and e.cooldown <= 0.0 and D6AiCommon.active_attackers(game) < game.tuning.combat.maxAttackers:
				D6AiCommon.set_state(e, "windup")
				D6Combat.spawn_hazard(game, {
					"shape": "circle", "x": e.x, "y": e.y, "r": def.slamRadius * (game.tuning.elite.sizeMult if D6Js.truthy(e.eliteMod) else 1.0),
					"delay": windup, "damage": def.damage * e.dmgScale, "kind": "brute", "sourceId": e.id,
				})
				return
			D6AiCommon.steer(game, e, p.x, p.y, D6AiCommon.speed_of(game, e, def))
		"windup":
			if e.stateTime >= windup:
				D6AiCommon.set_state(e, "recover")
				D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})
		"recover":
			_recover(e, def)
		_:
			D6AiCommon.set_state(e, "chase")

# ---------------------------------------------------------------- charger

static func _charger(game: Dictionary, e: Dictionary, def: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	var windup := D6AiCommon.windup_of(game, e, def.windup)
	match e.state:
		"chase":
			_charger_chase(game, e, def, p, tp)
		"windup":
			_charger_windup(game, e, def, windup)
		"charge":
			_charger_charge(game, e, def, dt, p)
		"recover":
			_recover(e, def)
		_:
			D6AiCommon.set_state(e, "chase")

static func _charger_chase(game: Dictionary, e: Dictionary, def: Dictionary, p: Dictionary, tp: Dictionary) -> void:
	var sees: bool = D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y)
	if tp.d < def.attackRange and sees and e.cooldown <= 0.0 and D6AiCommon.active_attackers(game) < game.tuning.combat.maxAttackers:
		D6AiCommon.set_state(e, "windup")
		e.dirX = tp.dx
		e.dirY = tp.dy
		e.hitPlayer = false
		e.atkId = D6State.new_id(game)
		return
	D6AiCommon.steer(game, e, p.x, p.y, D6AiCommon.speed_of(game, e, def))

static func _charger_windup(game: Dictionary, e: Dictionary, def: Dictionary, windup: float) -> void:
	D6AiCommon.track_until_lock(game, e, 0.7, windup)
	e.tele = {"shape": "line", "angle": D6Trig.atan2(e.dirY, e.dirX), "length": def.chargeSpeed * def.chargeMaxTime, "width": e.r * 2.0 + 10.0, "progress": e.stateTime / windup}
	if e.stateTime >= windup:
		e.tele = null
		D6AiCommon.set_state(e, "charge")
		D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})

static func _charger_charge(game: Dictionary, e: Dictionary, def: Dictionary, dt: float, p: Dictionary) -> void:
	e.vx = e.dirX * def.chargeSpeed
	e.vy = e.dirY * def.chargeSpeed
	var rr: float = e.r + p.r + 4.0
	if not e.hitPlayer and D6Geo.dist2(e.x, e.y, p.x, p.y) < rr * rr:
		e.hitPlayer = true
		D6Combat.damage_player(game, def.damage * e.dmgScale, {"kind": "charger", "id": e.atkId, "x": e.x, "y": e.y})
	# La charge se déplace ici (et non dans integrate) pour détecter le mur percuté.
	var res: Dictionary = D6Physics.move_circle(game.room, e, e.vx * dt, e.vy * dt)
	e.vx = 0.0
	e.vy = 0.0
	if res.hitWall:
		# Mur percuté : longue fenêtre de punition.
		e.stun = def.wallStun
		D6AiCommon.set_state(e, "stunned")
		game.telemetry.wallSlams += 1.0
		D6State.emit(game, "chargerWall", {"id": e.id, "x": e.x, "y": e.y})
	elif e.stateTime >= def.chargeMaxTime:
		D6AiCommon.set_state(e, "recover")

# ---------------------------------------------------------------- exploder

static func _exploder(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	match e.state:
		"chase":
			if tp.d < def.triggerRange + p.r:
				D6AiCommon.set_state(e, "windup")
				return
			D6AiCommon.steer(game, e, p.x, p.y, D6AiCommon.speed_of(game, e, def))
		"windup":
			var windup := D6AiCommon.windup_of(game, e, def.windup)
			e.tele = {"shape": "circle", "r": def.blastRadius, "progress": e.stateTime / windup}
			if e.stateTime >= windup:
				e.tele = null
				e.dead = true
				e.exploded = true
				D6Combat.spawn_hazard(game, {
					"shape": "circle", "x": e.x, "y": e.y, "r": def.blastRadius, "delay": 0.0,
					"damage": def.damage * e.dmgScale, "hitsPlayer": true, "hitsEnemies": def.get("blastHurtsEnemies"),
					"kind": "exploder", "ownerId": e.id,
				})
				D6State.emit(game, "explode", {"id": e.id, "x": e.x, "y": e.y, "r": def.blastRadius})
		_:
			D6AiCommon.set_state(e, "chase")

## Réexport de ai_common.windupOf.
static func windup_of(game: Dictionary, e: Dictionary, base: float) -> float:
	return D6AiCommon.windup_of(game, e, base)

static func alive_enemies(game: Dictionary) -> float:
	var n := 0.0
	for e in game.enemies:
		if not e.dead:
			n += 1.0
	return n
