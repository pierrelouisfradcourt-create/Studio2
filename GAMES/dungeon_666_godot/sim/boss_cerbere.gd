class_name D6BossCerbere
extends RefCounted
## Portage de src/sim/boss_cerbere.mjs.
## Gardien « Cerbère, le Chien des trois gueules » (modèle `cerbere`, section 2 puis en rotation).
## Bête RAPIDE qui ne laisse pas respirer : au repos elle RÔDE en cercle autour du héros au lieu de
## marcher sur lui, et attaque par séries de trois (trois têtes). Patterns, tous télégraphiés :
##   bond      — bonds annoncés par le CERCLE D'ATTERRISSAGE posé sous le héros (1 / 2 / 3 bonds
##               selon la phase) ; dès la phase 2 (bond.shockFromPhase), le dernier atterrissage
##               libère une onde (anneau) : rester dans le cercle qui vient de frapper, ou caler
##               les i-frames d'un dash sur l'onde. Après la série, il est ESSOUFFLÉ : immobile,
##               point faible exposé — la fenêtre de punition.
##   souffle   — les trois têtes crachent l'une après l'autre trois jets de flammes en éventail
##               (bandes qui partent de son centre) ; son DOS est sûr. Deux salves, ordre inversé,
##               dès la phase 2.
##   morsures  — trois ruées enchaînées, chacune re-visée et annoncée par un cône ; une ruée ne
##               mord QUE dans son cône dessiné (corps du héros compris). La dernière l'expose.
##   hurlement — (phase 3, frénésie) un cercle de flammes se referme autour du héros, avec une
##               brèche, puis Cerbère bondit en son centre : sortir par la brèche, ou dasher.
##
## Le moteur appelle tout pattern avec (game, e, d, dt, speed), JavaScript ignorant les arguments
## en trop : les fonctions qui en déclarent moins reçoivent ici des arguments de queue inutilisés.

const DEG := PI / 180.0
const LEAP_STATES := ["bond", "hurlement"]

static var _model = null

## Cri d'attaque : le son porte le timbre du Gardien (recipes.mjs, ENEMY_ATTACK.cerbere).
static func _bark(game: Dictionary, e: Dictionary) -> void:
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "cerbere"})

# ---------------------------------------------------------------- bond (brique partagée)

## Prépare un bond vers (tx, ty) : le cercle d'atterrissage apparaît AUSSITÔT (télégraphe de
## `delay` s) ; le chien s'accroupit, puis s'envole pendant les `air` dernières secondes et
## retombe à l'instant où le cercle frappe. En l'air, aucun dégât de contact.
static func _start_leap(game: Dictionary, e: Dictionary, b: Dictionary, tx: float, ty: float, delay: float, shock: bool) -> void:
	var pt := D6BossCommon.room_point(game, tx, ty, e.r)
	e.leap = {"x0": e.x, "y0": e.y, "x1": pt.x, "y1": pt.y, "t": 0.0, "delay": delay}
	D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": pt.x, "y": pt.y, "r": b.radius, "delay": delay, "damage": b.damage, "kind": "cerbereLand"})
	if shock:
		D6BossCommon.boss_hazard(game, e, {
			"shape": "ring", "x": pt.x, "y": pt.y, "r": b.radius + b.shockWidth, "inner": b.radius,
			"delay": delay + b.shockDelay, "damage": b.shockDamage, "kind": "cerbereShock",
		})

## Fait avancer le bond en cours ; rend true au pas de l'atterrissage.
static func _step_leap(game: Dictionary, e: Dictionary, b: Dictionary, dt: float) -> bool:
	var L: Dictionary = e.leap
	D6BossCommon.hold_still(e)
	L.t += dt
	var takeoff: float = L.delay - b.air
	if L.t < takeoff:
		return false
	if L.t < L.delay:
		var k: float = (L.t - takeoff) / b.air
		e.airborne = true
		e.leapK = k # hauteur du saut (dessin)
		e.x = L.x0 + (L.x1 - L.x0) * k
		e.y = L.y0 + (L.y1 - L.y0) * k
		return false
	e.x = L.x1
	e.y = L.y1
	e.airborne = false
	e.leapK = 0.0
	e.leap = null
	_bark(game, e)
	return true

static func bond(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var b: Dictionary = d.bond
	var leaps: float = b.leapsByPhase[int(e.phase) - 1]
	if e.get("sub") == "recover" or e.patternStep >= leaps:
		D6BossCommon.exposed_recovery(game, e, b.recover, b.exposedMult, dt)
		return
	if e.get("leap") == null:
		# Petite pause entre deux bonds d'une même série (le cercle suivant naît à l'atterrissage).
		e.subT += dt
		D6BossCommon.hold_still(e)
		if e.patternStep > 0 and e.subT < b.interval:
			return
		var p: Dictionary = game.player
		var last: bool = e.patternStep == leaps - 1.0
		_start_leap(game, e, b, p.x, p.y, b.windup, last and e.phase >= b.shockFromPhase)
	if _step_leap(game, e, b, dt):
		e.patternStep += 1
		e.subT = 0.0

# ---------------------------------------------------------------- souffle

static func _volley(game: Dictionary, e: Dictionary, s: Dictionary, index: float) -> void:
	var tp := D6BossCommon.to_player(game, e)
	var aim := D6Trig.atan2(tp.dy, tp.dx)
	# Sens de la salve (gauche -> droite ou l'inverse) : tiré pour la 1re, alterné ensuite.
	if index == 0.0:
		e.breathDir = 1.0 if D6Rng.rand(game.rng.ai) < 0.5 else -1.0
	else:
		e.breathDir = -e.breathDir
	var n: float = s.jets
	for idx in range(int(n)):
		var i := float(idx)
		var rank: float = i if e.breathDir > 0.0 else n - 1.0 - i
		var a: float = aim + (i - (n - 1.0) / 2.0) * s.spreadDeg * DEG
		D6BossCommon.boss_hazard(game, e, {
			"shape": "line", "x": e.x, "y": e.y, "angle": a, "length": s.length, "width": s.width,
			"delay": s.windup + rank * s.step, "damage": s.damage, "kind": "cerbereFlame",
		})
	_bark(game, e)

static func souffle(game: Dictionary, e: Dictionary, d: Dictionary, _dt: float = 0.0, _speed: float = 0.0) -> void:
	var s: Dictionary = d.souffle
	D6BossCommon.hold_still(e)
	var volleys: float = s.volleysByPhase[int(e.phase) - 1]
	var length: float = s.windup + (s.jets - 1.0) * s.step # dernier jet d'une salve
	var period: float = length + s.volleyGap
	if e.patternStep < volleys and e.stateTime >= e.patternStep * period:
		_volley(game, e, s, e.patternStep)
		e.patternStep += 1
	if e.stateTime >= (volleys - 1.0) * period + length:
		D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- morsures

## Portée du cône dessiné : la course de la ruée + le corps + la marge (morsures.telePad).
static func _bite_range(e: Dictionary, m: Dictionary) -> float:
	return m.strikeSpeed * m.strikeTime + e.r + m.telePad

static func morsures(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, speed: float) -> void:
	var m: Dictionary = d.morsures
	if e.patternStep >= m.bites:
		# Dernière morsure : la gueule reste plantée, le flanc est exposé.
		D6BossCommon.exposed_recovery(game, e, m.finalRecover, m.exposedMult, dt)
		return
	if not D6Js.truthy(e.get("sub")):
		D6BossCommon.set_sub(e, "approach")
	e.subT += dt
	match e.sub:
		"approach":
			_bite_approach(game, e, m, speed)
		"windup":
			_bite_windup(game, e, m)
		"strike":
			_bite_strike(game, e, m)
		_: # 'gap' : souffle court entre deux morsures
			D6BossCommon.hold_still(e)
			if e.subT >= m.recover:
				D6BossCommon.set_sub(e, "windup")

## Trop loin pour mordre : il fonce (aucun dégât de contact), au plus `approachMax` s.
static func _bite_approach(game: Dictionary, e: Dictionary, m: Dictionary, speed: float) -> void:
	var tp := D6BossCommon.to_player(game, e)
	if tp.d <= _bite_range(e, m) * m.engageFrac or e.subT >= m.approachMax:
		D6BossCommon.set_sub(e, "windup")
		return
	e.vx = tp.dx * speed * m.approachMult
	e.vy = tp.dy * speed * m.approachMult

static func _bite_windup(game: Dictionary, e: Dictionary, m: Dictionary) -> void:
	D6BossCommon.hold_still(e)
	# La gueule suit le héros, puis se fige (lockAt) : la ruée part là où le cône le montre.
	if e.subT < m.windup * m.lockAt:
		var tp := D6BossCommon.to_player(game, e)
		e.dirX = tp.dx
		e.dirY = tp.dy
	e.tele = {"shape": "cone", "angle": D6Trig.atan2(e.dirY, e.dirX), "range": _bite_range(e, m), "arc": m.arcDeg * DEG, "progress": e.subT / m.windup}
	if e.subT >= m.windup:
		e.tele = null
		e.hitPlayer = false
		e.atkId = D6State.new_id(game)
		# Origine du cône dessiné : la ruée ne mordra que dedans.
		e.biteX = e.x
		e.biteY = e.y
		D6BossCommon.set_sub(e, "strike")
		_bark(game, e)

static func _bite_strike(game: Dictionary, e: Dictionary, m: Dictionary) -> void:
	var p: Dictionary = game.player
	e.vx = e.dirX * m.strikeSpeed
	e.vy = e.dirY * m.strikeSpeed
	# Contact de la gueule (morsures.hitPad) ET corps du héros dans le cône annoncé : la ruée
	# ne déborde jamais du télégraphe (près de l'apex, le contact seul dépasserait du cône).
	var in_cone := D6Geo.in_sector(p.x, p.y, e.biteX, e.biteY, _bite_range(e, m), D6Trig.atan2(e.dirY, e.dirX), m.arcDeg * DEG, p.r)
	var reach: float = e.r + p.r + m.hitPad
	if not D6Js.truthy(e.get("hitPlayer")) and in_cone and D6Geo.dist2(e.x, e.y, p.x, p.y) < reach * reach:
		e.hitPlayer = true
		D6Combat.damage_player(game, m.damage * e.dmgScale, {"kind": "cerbereBite", "id": e.atkId, "x": e.x, "y": e.y})
	if e.subT >= m.strikeTime:
		e.patternStep += 1
		D6BossCommon.set_sub(e, "gap")

# ---------------------------------------------------------------- hurlement (phase 3)

static func hurlement(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var h: Dictionary = d.hurlement
	var b: Dictionary = d.bond
	if e.get("sub") == "recover" or (e.get("leap") == null and e.patternStep > 0):
		D6BossCommon.exposed_recovery(game, e, b.recover, b.exposedMult, dt)
		return
	if e.get("leap") == null:
		var p: Dictionary = game.player
		var room: Dictionary = game.room
		var c := D6BossCommon.room_point(game, p.x, p.y, e.r)
		# Couronne de flammes autour du héros, avec une brèche de `gaps` flammes à un angle tiré.
		var a0 := D6Rng.rand(game.rng.ai) * TAU
		var k: float = h.gaps
		while k < h.flames:
			var a: float = a0 + (k / h.flames) * TAU
			var fx := D6Geo.clampv(c.x + D6Trig.cos(a) * h.ringRadius, room.pad, room.w - room.pad)
			var fy := D6Geo.clampv(c.y + D6Trig.sin(a) * h.ringRadius, room.pad, room.h - room.pad)
			D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": fx, "y": fy, "r": h.flameRadius, "delay": h.delay, "damage": h.damage, "kind": "cerbereFire"})
			k += 1.0
		# ... et le chien bondit au centre, juste après.
		_start_leap(game, e, b, c.x, c.y, h.leapDelay, false)
		e.patternStep = 1.0
		_bark(game, e)
	if _step_leap(game, e, b, dt):
		D6BossCommon.exposed_recovery(game, e, b.recover, b.exposedMult, 0.0)

# ---------------------------------------------------------------- repos : il rôde

## Au repos, Cerbère tourne autour du héros à distance (`prowl.dist`) au lieu de l'approcher.
static func _prowl(game: Dictionary, e: Dictionary, d: Dictionary, _dt: float, speed: float) -> void:
	var pr: Dictionary = d.prowl
	var p: Dictionary = game.player
	var dx: float = e.x - p.x
	var dy: float = e.y - p.y
	var dd := maxf(1e-6, sqrt(dx * dx + dy * dy))
	var ux := dx / dd
	var uy := dy / dd
	var radial: float = D6Geo.clampv((pr.dist - dd) / pr.dist, -1.0, 1.0) * pr.radialGain # > 0 : trop près, il s'écarte
	var vx: float = -uy * e.strafe + ux * radial
	var vy: float = ux * e.strafe + uy * radial
	var l := maxf(1e-6, sqrt(vx * vx + vy * vy))
	e.vx = (vx / l) * speed
	e.vy = (vy / l) * speed

## À chaque pas : un bond interrompu (transition de phase) ne laisse pas le chien « en l'air ».
static func _tick(_game: Dictionary, e: Dictionary, _d: Dictionary = {}, _dt: float = 0.0) -> void:
	if not LEAP_STATES.has(e.state) and (e.get("leap") != null or D6Js.truthy(e.get("airborne"))):
		e.leap = null
		e.airborne = false
		e.leapK = 0.0

## CERBERE. Bonds, morsures et souffle d'emblée (le souffle double sa salve dès la phase 2) ; la
## frénésie (hurlement) s'ajoute en phase 3. Construit une fois, PARTAGÉ : ne pas le modifier.
static func model() -> Dictionary:
	if _model == null:
		_model = {
			"byPhase": {"1": ["bond", "morsures", "souffle"], "2": ["bond", "morsures", "souffle"], "3": ["bond", "morsures", "souffle", "hurlement"]},
			"patterns": {"bond": bond, "souffle": souffle, "morsures": morsures, "hurlement": hurlement},
			"rest": _prowl,
			"tick": _tick,
		}
	return _model
