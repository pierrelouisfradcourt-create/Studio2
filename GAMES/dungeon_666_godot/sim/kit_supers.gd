class_name D6KitSupers
extends RefCounted
## Portage de src/sim/kit_supers.mjs.
## SUPERS autres que la Colère, joués selon `kind`. player garde l'état 'super' (le héros
## y est invulnérable : combat), la durée, la locomotion et la fin ; ce module ne fait que
## le « tic » propre au Super :
##   sentence — Sentence (Bourreau) : exécutions auto-visées à des instants fixes du Super
##   nuee     — Nuée de traits (Chasseresse) : un trait toutes les `interval` s sur les ennemis
##              les plus proches, en rotation
## Les dégâts portent la source 'super' (ils ne rechargent pas la jauge ; « Gloire charnelle »
## s'y applique).

static func start_kit_super(game: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superClock = 0.0
	p.superStep = 0.0
	p.superShotT = 0.0
	p.superRot = 0.0

static func tick_kit_super(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superClock += dt
	if s.kind == "sentence":
		_sentence(game, s)
	elif s.kind == "nuee":
		_nuee(game, dt, s)

static func _sentence(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var strikes: Array = s.strikes
	while p.superStep < float(strikes.size()) and p.superClock >= strikes[int(p.superStep)].at:
		var st: Dictionary = strikes[int(p.superStep)]
		p.superStep += 1.0
		var aim: Dictionary = D6Aim.compute_aim(game, p.manualAimX, p.manualAimY, s.get("aimRange"))
		var angle: float = D6Trig.atan2(aim.y, aim.x)
		p.facing = angle
		D6KitCommon.hit_sector(game, p.x, p.y, st.range, angle, st.arc * D6Data.DEG, {
			"kind": "super", "amount": st.damage, "knockback": st.knockback, "stun": D6Js.nz(st.get("stun"), 0.0), "hitstop": st.hitstop, "canCrit": true, "shake": D6Js.nz(st.get("shake"), 0.0),
		})
		D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": st.range, "super": "sentence", "angle": angle, "arc": st.arc * D6Data.DEG, "step": p.superStep})

## Les `n` ennemis visibles les plus proches à portée, du plus proche au plus lointain.
static func _nearest_targets(game: Dictionary, reach_max: float, n: float) -> Array:
	var p: Dictionary = game.player
	var list: Array = []
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		var d2: float = D6Geo.dist2(p.x, p.y, e.x, e.y)
		var reach: float = reach_max + e.r
		if d2 > reach * reach:
			continue
		if not D6Physics.line_of_sight(game.room, p.x, p.y, e.x, e.y):
			continue
		list.append({"e": e, "d2": d2})
	# Tri par distance puis par id : ordre TOTAL (ids uniques), la stabilité du tri ne joue pas.
	list.sort_custom(func(a, b): return a.d2 < b.d2 or (a.d2 == b.d2 and a.e.id < b.e.id))
	return list.slice(0, maxi(0, int(n)))

static func _nuee(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superShotT -= dt
	if p.superShotT > 0.0:
		return
	p.superShotT += s.interval
	var targets: Array = _nearest_targets(game, s.range, s.targets)
	if targets.size() == 0:
		return
	var e: Dictionary = targets[int(fmod(p.superRot, float(targets.size())))].e
	p.superRot += 1.0
	var dx: float = e.x - p.x
	var dy: float = e.y - p.y
	var l: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	D6KitShots.spawn_shot(game, {
		"kind": "star", "x": p.x, "y": p.y, "vx": (dx / l) * s.speed, "vy": (dy / l) * s.speed, "r": s.shotRadius, "range": s.range,
		"pierce": s.pierce, "damage": s.damage, "source": "super", "knockback": s.knockback, "hitstop": s.hitstop, "heavy": false,
	})
	D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": s.shotRadius, "super": "nuee", "angle": D6Trig.atan2(dy, dx)})
