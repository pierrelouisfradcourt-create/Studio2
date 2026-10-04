class_name D6BossCharon
extends RefCounted
## Portage de src/sim/boss_charon.mjs.
## Gardien « Charon, le Passeur » (modèle `gardien`, section 1 puis en rotation).
## Patterns enchaînés, chacun télégraphié :
##   slam   — trois impacts circulaires successifs, posés là où se trouve le héros
##   charge — ligne télégraphiée puis ruée ; s'il percute un mur, il reste sonné (punition)
##   ring   — anneaux de projectiles avec des brèches : lire, se placer, dasher à travers
##   summon — (phase 3) invoque des diablotins via des cercles d'invocation (alerte inoffensive)
##
## Le moteur appelle tout pattern avec (game, e, d, dt, speed), JavaScript ignorant les arguments
## en trop : les patterns qui en déclarent moins reçoivent ici des arguments de queue inutilisés.

const CHARGE_HIT_PAD := 4.0 # u ajoutés au contact boss/héros pendant la charge

static var _model = null

static func slam(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, speed: float) -> void:
	var s: Dictionary = d.slam
	var p: Dictionary = game.player
	e.patternT -= dt
	var tp := D6BossCommon.to_player(game, e)
	e.vx = tp.dx * speed * s.approachMult
	e.vy = tp.dy * speed * s.approachMult
	if e.patternStep < s.count and e.patternT <= 0.0:
		D6Combat.spawn_hazard(game, {
			"shape": "circle", "x": p.x, "y": p.y, "r": s.radius, "delay": s.windup * D6BossCommon.wmult(),
			"damage": s.damage * e.dmgScale, "kind": "bossSlam", "sourceId": 0.0,
		})
		e.patternStep += 1
		e.patternT = s.interval * D6BossCommon.wmult()
	if e.patternStep >= s.count and e.stateTime >= s.interval * s.count + s.windup:
		D6BossCommon.to_rest(game, e)

static func charge(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var c: Dictionary = d.charge
	var windup: float = d.secondChargeWindup if D6Js.truthy(e.get("secondCharge")) else c.windup * D6BossCommon.wmult()
	if e.patternStep == 0:
		_charge_windup(game, e, c, windup)
		return
	_charge_rush(game, e, c, dt)

## Charge, étape 0 : la ligne suit le héros (la part `lockAt` du télégraphe), puis se fige.
static func _charge_windup(game: Dictionary, e: Dictionary, c: Dictionary, windup: float) -> void:
	if e.stateTime < windup * c.lockAt:
		var tp := D6BossCommon.to_player(game, e)
		e.dirX = tp.dx
		e.dirY = tp.dy
	# Largeur = zone qui touche réellement (rayon du boss + marge du test de contact) : esquiver
	# « au pixel » le bord rouge doit toujours suffire.
	e.tele = {
		"shape": "line", "angle": D6Trig.atan2(e.dirY, e.dirX), "length": c.speed * c.maxTime,
		"width": maxf(c.width, 2.0 * (e.r + CHARGE_HIT_PAD)), "progress": e.stateTime / windup,
	}
	if e.stateTime >= windup:
		e.tele = null
		e.patternStep = 1.0
		e.patternT = 0.0
		e.hitPlayer = false
		e.atkId = game.nextId
		game.nextId += 1
		D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "boss"})

## Charge, étape 1 : la ruée.
static func _charge_rush(game: Dictionary, e: Dictionary, c: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	e.patternT += dt
	var res = D6Physics.move_circle(game.room, e, e.dirX * c.speed * dt, e.dirY * c.speed * dt)
	var reach: float = e.r + p.r + CHARGE_HIT_PAD
	if not D6Js.truthy(e.get("hitPlayer")) and D6Geo.dist2(e.x, e.y, p.x, p.y) < reach * reach:
		e.hitPlayer = true
		D6Combat.damage_player(game, c.damage * e.dmgScale, {"kind": "bossCharge", "id": e.atkId, "x": e.x, "y": e.y})
	if res.hitWall or res.hitLow:
		# Mur — ou bord d'un terrain bas : la ruée ne franchit rien.
		# set_state : l'étape et le chronomètre de la ruée ne survivent pas au pattern interrompu.
		D6BossCommon.set_state(e, "stunned")
		e.stun = c.wallStun
		game.telemetry.wallSlams += 1
		D6State.emit(game, "chargerWall", {"id": e.id, "x": e.x, "y": e.y, "boss": true})
	elif e.patternT >= c.maxTime:
		if e.phase == 3 and not D6Js.truthy(e.get("secondCharge")):
			# Phase 3 : seconde traversée enchaînée, avec son propre télégraphe.
			e.secondCharge = true
			D6BossCommon.set_state(e, "charge")
			return
		D6BossCommon.to_rest(game, e)

static func ring(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var r: Dictionary = d.ring
	var windup: float = r.windup * D6BossCommon.wmult()
	if e.patternStep == 0:
		e.tele = {"shape": "circle", "r": r.teleRadius, "progress": e.stateTime / windup}
		if e.stateTime >= windup:
			e.tele = null
			e.patternStep = 1.0
			e.patternT = 0.0
		return
	e.patternT -= dt
	var waves: float = r.waves + (e.phase - 1)
	# Salve en cours : le cercle d'alerte reste affiché et se remplit avant chaque vague, pour
	# qu'on ne revienne pas au contact sous le tir suivant.
	if e.patternStep <= waves:
		e.tele = {"shape": "circle", "r": r.teleRadius, "progress": 1.0 - maxf(0.0, e.patternT) / r.waveInterval}
	if e.patternStep <= waves and e.patternT <= 0.0:
		_ring_wave(game, e, r)
		e.patternStep += 1
		e.patternT = r.waveInterval
	if e.patternStep > waves:
		D6BossCommon.to_rest(game, e)

## Une vague de l'anneau. Brèches contiguës à un angle aléatoire : il y a toujours un couloir sûr.
static func _ring_wave(game: Dictionary, e: Dictionary, r: Dictionary) -> void:
	var n: float = r.bullets
	var gap_start := floorf(D6Rng.rand(game.rng.ai) * n)
	var offset := fmod(float(e.patternStep), 2.0) * (PI / n)
	for idx in range(int(n)):
		var i := float(idx)
		var rel := fmod(i - gap_start + n, n)
		if rel < r.gapCount:
			continue
		var a := offset + (i / n) * PI * 2.0
		D6Projectiles.spawn_projectile(game, {
			"owner": "enemy", "kind": "bossOrb", "x": e.x + D6Trig.cos(a) * e.r, "y": e.y + D6Trig.sin(a) * e.r,
			"vx": D6Trig.cos(a) * r.speed, "vy": D6Trig.sin(a) * r.speed, "r": r.radius, "damage": r.damage * e.dmgScale,
			"range": r.range, "sourceId": e.id,
		})
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "bossRing"})

static func summon(game: Dictionary, e: Dictionary, d: Dictionary, _dt: float = 0.0, _speed: float = 0.0) -> void:
	var s: Dictionary = d.summon
	if e.patternStep == 0:
		# Invocation : alerte inoffensive, dessinée autrement que le rouge « ça fait mal ».
		e.tele = {"shape": "circle", "r": s.teleRadius, "progress": e.stateTime / s.windup, "harmless": true}
		if e.stateTime >= s.windup:
			e.tele = null
			for i in range(int(s.count)):
				var pt = D6Spawns.find_spawn_point(game, 14.0, s.minPlayerDist, {"x": e.x, "y": e.y, "minR": e.r + s.minR, "maxR": e.r + s.maxR})
				if pt != null:
					D6Spawns.queue_spawn(game, s.kind, pt.x, pt.y, {"summoned": true})
			e.patternStep = 1.0
			D6State.emit(game, "bossSummon", {"id": e.id, "x": e.x, "y": e.y})
		return
	D6BossCommon.to_rest(game, e)

## CHARON. Patterns disponibles par phase : la charge arrive en phase 2, les invocations en
## phase 3. Construit une fois, PARTAGÉ : ne pas le modifier.
static func model() -> Dictionary:
	if _model == null:
		_model = {
			"byPhase": {"1": ["slam", "ring"], "2": ["slam", "ring", "charge"], "3": ["slam", "ring", "charge", "summon"]},
			"patterns": {"slam": slam, "charge": charge, "ring": ring, "summon": summon},
		}
	return _model
