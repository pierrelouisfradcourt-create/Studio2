class_name D6BossMinos
extends RefCounted
## Portage de src/sim/boss_minos.mjs.
## Gardien « Minos, le Juge des damnés » (modèle `minos`, section 3 puis en rotation).
## Contrôle de l'ARÈNE : il ne poursuit jamais. Il siège (dérive lente vers son trône) et rend
## l'espace dangereux par motifs géométriques. Patterns, tous télégraphiés :
##   sentence — bandes parallèles qui BALAIENT l'arène l'une après l'autre ; chacune a une brèche.
##              Phase 1 : brèches alignées (un couloir) ; phase 2 : une brèche par bande ;
##              phase 3 : un second balayage perpendiculaire. Contre-jeu : la brèche de sa bande,
##              une bande qui vient de frapper, ou un dash à travers (bande < portée du dash).
##   jugement — dalles en damier autour du héros, en deux (phase 3 : trois) temps ; la dalle du
##              héros frappe toujours la première : passer sur une dalle voisine, puis revenir.
##   fouet    — sa queue balaie 360° autour de lui SAUF une brèche (jamais du côté du héros) ;
##              phase 2+ : second coup, brèche ailleurs. Après le fouet, il se découvre.
##   sceau    — (phase 2+) il se dissout et se matérialise sur le héros : la sentence tombe en
##              COURONNE autour du point d'arrivée — rester au centre (contre lui) ou fuir loin.
##              Phase 3 : le fouet suit aussitôt.
##
## Le moteur appelle tout pattern avec (game, e, d, dt, speed), JavaScript ignorant les arguments
## en trop : les fonctions qui en déclarent moins reçoivent ici des arguments de queue inutilisés.

const DEG := PI / 180.0

static var _model = null

## Coup de marteau du Juge : le son porte son timbre (recipes.mjs, ENEMY_ATTACK.minos).
static func _gavel(game: Dictionary, e: Dictionary) -> void:
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "minos"})

## Il incante : alerte INOFFENSIVE autour de lui (le danger, lui, est dessiné au sol en rouge).
static func _chant(e: Dictionary, d: Dictionary, progress: float) -> void:
	e.tele = {"shape": "circle", "r": e.r + d.chantPad, "progress": D6Geo.clampv(progress, 0.0, 1.0), "harmless": true}

# ---------------------------------------------------------------- sentence

## Brèche tirée à portée de marche du héros (sur l'axe des bandes), bornée à la salle.
static func _breach_at(game: Dictionary, s: Dictionary, ref: float, along: float) -> float:
	var lo: float = game.room.pad + s.breach / 2.0
	var hi: float = along - game.room.pad - s.breach / 2.0
	return D6Geo.clampv(ref + D6Rng.rand_range(game.rng.ai, -s.breachReach, s.breachReach), lo, hi)

## Un balayage : `n` bandes jointives perpendiculaires à l'axe, qui frappent dans l'ordre
## (pas `step`) ; chaque bande = deux segments de part et d'autre de sa brèche.
## horizontal : bandes horizontales (balayage haut <-> bas). Rend la durée jusqu'au dernier coup.
static func _sweep(game: Dictionary, e: Dictionary, s: Dictionary, horizontal: bool, forward: bool, shared_breach: bool) -> float:
	var room: Dictionary = game.room
	var p: Dictionary = game.player
	var n: float = s.bandsH if horizontal else s.bandsV
	var span: float = (room.h if horizontal else room.w) - 2.0 * room.pad
	var along: float = room.w if horizontal else room.h
	var band := span / n
	var ref: float = p.x if horizontal else p.y
	var shared := _breach_at(game, s, ref, along)
	for idx in range(int(n)):
		var i := float(idx)
		var rank := i if forward else n - 1.0 - i
		var c: float = room.pad + (i + 0.5) * band
		var b := shared if shared_breach else _breach_at(game, s, ref, along)
		var delay: float = s.delay + rank * s.step
		for seg in [[room.pad, b - s.breach / 2.0], [b + s.breach / 2.0, along - room.pad]]:
			var a0: float = seg[0]
			var a1: float = seg[1]
			if a1 - a0 <= 0.0:
				continue
			var hz := {"shape": "line"}
			if horizontal:
				hz.merge({"x": a0, "y": c, "angle": 0.0}, true)
			else:
				hz.merge({"x": c, "y": a0, "angle": PI / 2.0}, true)
			hz.merge({"length": a1 - a0, "width": band, "delay": delay, "damage": s.damage, "kind": "minosSentence"}, true)
			D6BossCommon.boss_hazard(game, e, hz)
	_gavel(game, e)
	return s.delay + (n - 1.0) * s.step

static func sentence(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var s: Dictionary = d.sentence
	D6BossCommon.hold_still(e)
	var sweeps := 2.0 if e.phase >= s.crossFromPhase else 1.0
	if not D6Js.truthy(e.get("sub")):
		e.sweepH = D6Rng.rand(game.rng.ai) < 0.5
		var forward := D6Rng.rand(game.rng.ai) < 0.5
		e.sweepEnd = _sweep(game, e, s, e.sweepH, forward, e.phase < s.ownBreachFromPhase)
		e.patternStep = 1.0
		D6BossCommon.set_sub(e, "sweep")
	e.subT += dt
	_chant(e, d, e.subT / e.sweepEnd)
	if e.subT < e.sweepEnd:
		return
	if e.patternStep < sweeps:
		# Phase 3 : la croix — le second balayage, perpendiculaire, naît quand le premier s'achève.
		if e.subT < e.sweepEnd + s.crossGap:
			return
		e.sweepH = not e.sweepH
		var forward2 := D6Rng.rand(game.rng.ai) < 0.5
		e.sweepEnd = _sweep(game, e, s, e.sweepH, forward2, false)
		e.patternStep += 1
		e.subT = 0.0
		return
	D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- jugement

## Une vague de dalles : les cases de parité `parity` (0 = celle du héros) autour de lui.
static func _tile_wave(game: Dictionary, e: Dictionary, j: Dictionary, parity: float) -> void:
	var room: Dictionary = game.room
	var s: float = j.spacing
	var cols := floorf((room.w - 2.0 * room.pad) / s)
	var rows := floorf((room.h - 2.0 * room.pad) / s)
	var ox: float = (room.w - cols * s) / 2.0
	var oy: float = (room.h - rows * s) / 2.0
	var r: float = s * j.radiusMult
	var tile_i: float = e.tileI
	var tile_j: float = e.tileJ
	var reach: float = j.reach
	var i := maxf(0.0, tile_i - reach)
	while i <= minf(cols - 1.0, tile_i + reach):
		var k := maxf(0.0, tile_j - reach)
		while k <= minf(rows - 1.0, tile_j + reach):
			if fmod(i + k + tile_i + tile_j, 2.0) == parity:
				D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": ox + (i + 0.5) * s, "y": oy + (k + 0.5) * s, "r": r, "delay": j.delay, "damage": j.damage, "kind": "minosTile"})
			k += 1.0
		i += 1.0
	_gavel(game, e)

static func jugement(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var j: Dictionary = d.jugement
	D6BossCommon.hold_still(e)
	var waves: float = j.wavesByPhase[int(e.phase) - 1]
	if not D6Js.truthy(e.get("sub")):
		# Le damier est calé sur la case du héros AU DÉBUT : sa case frappe en premier.
		var room: Dictionary = game.room
		var cols := floorf((room.w - 2.0 * room.pad) / j.spacing)
		var rows := floorf((room.h - 2.0 * room.pad) / j.spacing)
		var p: Dictionary = game.player
		e.tileI = D6Geo.clampv(floorf((p.x - (room.w - cols * j.spacing) / 2.0) / j.spacing), 0.0, cols - 1.0)
		e.tileJ = D6Geo.clampv(floorf((p.y - (room.h - rows * j.spacing) / 2.0) / j.spacing), 0.0, rows - 1.0)
		D6BossCommon.set_sub(e, "tiles")
	e.subT += dt
	# Vague w posée à w × gap : au plus deux vagues visibles, chacune télégraphiée `delay` s.
	while e.patternStep < waves and e.subT >= e.patternStep * j.gap:
		_tile_wave(game, e, j, fmod(float(e.patternStep), 2.0))
		e.patternStep += 1
	var end: float = (waves - 1.0) * j.gap + j.delay
	_chant(e, d, e.subT / end)
	if e.subT >= end:
		D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- fouet

static func fouet(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var f: Dictionary = d.fouet
	var p: Dictionary = game.player
	D6BossCommon.hold_still(e)
	var whips := 2.0 if e.phase >= f.doubleFromPhase else 1.0
	if e.get("sub") == "recover" or e.patternStep >= whips:
		D6BossCommon.exposed_recovery(game, e, f.recover, f.exposedMult, dt)
		return
	var windup: float = f.windup if e.patternStep == 0 else f.secondWindup
	if e.get("sub") != "whip":
		# Brèche à au moins `minOffsetDeg` du côté du héros : il faut toujours bouger.
		var tp := D6BossCommon.to_player(game, e)
		var side := -1.0 if D6Rng.rand(game.rng.ai) < 0.5 else 1.0
		var min_off: float = f.minOffsetDeg * DEG
		e.breachAngle = D6Trig.atan2(tp.dy, tp.dx) + side * (min_off + D6Rng.rand(game.rng.ai) * (PI - min_off))
		D6BossCommon.set_sub(e, "whip")
	e.subT += dt
	var arc: float = TAU - f.breachDeg * DEG
	var angle: float = e.breachAngle + PI
	# Cône « de zone » (area) : le corps ne bouge pas, tout le secteur frappe d'un coup.
	e.tele = {"shape": "cone", "area": true, "angle": angle, "range": f["range"], "arc": arc, "progress": e.subT / windup}
	if e.subT < windup:
		return
	e.tele = null
	_gavel(game, e)
	if D6Geo.in_sector(p.x, p.y, e.x, e.y, f["range"], angle, arc, p.r):
		D6Combat.damage_player(game, f.damage * e.dmgScale, {"kind": "minosWhip", "id": D6State.new_id(game), "x": e.x, "y": e.y})
	e.patternStep += 1
	D6BossCommon.set_sub(e, "next")

# ---------------------------------------------------------------- sceau (téléportation)

static func sceau(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var s: Dictionary = d.sceau
	D6BossCommon.hold_still(e)
	if not D6Js.truthy(e.get("sub")):
		var p: Dictionary = game.player
		var pt := D6BossCommon.room_point(game, p.x, p.y, e.r)
		e.sealX = pt.x
		e.sealY = pt.y
		D6BossCommon.boss_hazard(game, e, {"shape": "ring", "x": pt.x, "y": pt.y, "r": s.outer, "inner": s.inner, "delay": s.delay, "damage": s.damage, "kind": "minosSeal"})
		e.hidden = true # dissous : intouchable, dessiné en filigrane (art_bosses.mjs)
		D6BossCommon.set_sub(e, "vanish")
		_gavel(game, e)
	e.subT += dt
	if e.subT < s.delay:
		e.invuln = maxf(e.invuln, s.delay - e.subT)
		return
	e.x = e.sealX
	e.y = e.sealY
	e.hidden = false
	e.invuln = 0.0
	_gavel(game, e)
	if e.phase >= s.whipFromPhase:
		# Phase 3 : à peine matérialisé, il fouette (son propre télégraphe, jamais raccourci).
		e.pattern = "fouet"
		D6BossCommon.set_state(e, "fouet")
		return
	D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- repos : il siège

## Au repos, Minos regagne lentement son trône ; il ne court jamais après le héros.
static func _sit(game: Dictionary, e: Dictionary, d: Dictionary, _dt: float, speed: float) -> void:
	var room: Dictionary = game.room
	var tx: float = room.w * d.throne.fx
	var ty: float = room.h * d.throne.fy
	var dx: float = tx - e.x
	var dy: float = ty - e.y
	var l := sqrt(dx * dx + dy * dy)
	if l < d.throne.settle:
		return
	e.vx = (dx / l) * speed
	e.vy = (dy / l) * speed

## À chaque pas : un sceau interrompu ne laisse jamais Minos invisible.
static func _tick(_game: Dictionary, e: Dictionary, _d: Dictionary = {}, _dt: float = 0.0) -> void:
	if D6Js.truthy(e.get("hidden")) and e.state != "sceau":
		e.hidden = false

## MINOS. Sentence, fouet et jugement d'emblée ; le sceau en phase 2 ; tout s'enchaîne en phase 3.
## Construit une fois, PARTAGÉ : ne pas le modifier.
static func model() -> Dictionary:
	if _model == null:
		_model = {
			"byPhase": {"1": ["sentence", "fouet", "jugement"], "2": ["sentence", "fouet", "jugement", "sceau"], "3": ["sentence", "fouet", "jugement", "sceau"]},
			"patterns": {"sentence": sentence, "jugement": jugement, "fouet": fouet, "sceau": sceau},
			"rest": _sit,
			"tick": _tick,
		}
	return _model
