class_name D6Aim
extends RefCounted
## Portage de src/sim/aim.mjs.
## Visée assistée — décisive sur mobile : un tap sur « attaque » vise l'ennemi le plus
## pertinent (proche ET dans la direction où l'on se déplace). La visée manuelle (souris,
## joystick d'attaque glissé) l'emporte toujours. Réglages : tuning.autoAim (stickyTime : s pendant
## lesquelles la cible précédente reste privilégiée ; stickyBonus, threatBonus, eliteBonus : u
## retirées au score de la cible précédente, d'un ennemi qui prépare une attaque, d'un champion).

const MANUAL_DEADZONE := 0.15 # en deçà, la visée manuelle est ignorée
const MOVE_DEADZONE := 0.2 # en deçà, le mouvement ne donne pas la direction de préférence
const NEVER_TARGETED := -99.0
const TINY := 1e-6

static var _out := {"x": 0.0, "y": -1.0, "targetId": 0.0, "targetDist": 0.0}

## Rend un objet PARTAGÉ {x, y, targetId, targetDist} : direction unitaire de visée.
## `manual_x/manual_y` : visée explicite (0, 0 = aucune). `aim_range` (le `range` du JavaScript,
## nom réservé ici) : portée, null = autoAim.range.
static func compute_aim(game: Dictionary, manual_x: float, manual_y: float, aim_range = null) -> Dictionary:
	var p: Dictionary = game.player
	var a: Dictionary = game.tuning.autoAim
	var max_range: float = D6Js.nz(aim_range, a.range)
	_out.targetId = 0.0
	_out.targetDist = 0.0
	var ml := sqrt(manual_x * manual_x + manual_y * manual_y)
	if ml > MANUAL_DEADZONE:
		_out.x = manual_x / ml
		_out.y = manual_y / ml
		return _out
	# Direction de préférence : le mouvement en cours, sinon l'orientation.
	var px: float = p.moveX
	var py: float = p.moveY
	var pl := sqrt(px * px + py * py)
	if pl > MOVE_DEADZONE:
		px /= pl
		py /= pl
	else:
		px = D6Trig.cos(p.facing)
		py = D6Trig.sin(p.facing)
	var found := _best_target(game, px, py, max_range)
	if found.best != null:
		var best: Dictionary = found.best
		var best_d: float = found.d
		var dx: float = best.x - p.x
		var dy: float = best.y - p.y
		var d := maxf(TINY, best_d)
		_out.x = dx / d
		_out.y = dy / d
		_out.targetId = best.id
		_out.targetDist = best_d
		return _out
	_out.x = px
	_out.y = py
	return _out

## La boucle de choix de cible de computeAim : rend {best: ennemi ou null, d: sa distance}.
static func _best_target(game: Dictionary, px: float, py: float, max_range: float) -> Dictionary:
	var p: Dictionary = game.player
	var a: Dictionary = game.tuning.autoAim
	var cos_cone := D6Trig.cos((a.coneDeg / 2.0) * D6Data.DEG)
	var best = null
	var best_score := INF
	var best_d := 0.0
	var sticky = p.lastTargetId if game.time - D6Js.nz(p.get("lastTargetAt"), NEVER_TARGETED) < a.stickyTime else 0.0
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		var dx: float = e.x - p.x
		var dy: float = e.y - p.y
		var d := sqrt(dx * dx + dy * dy)
		var reach: float = max_range + e.r
		if d > reach:
			continue
		# Jamais à travers un pilier : on ne vise que ce qu'on peut atteindre.
		if not D6Physics.line_of_sight(game.room, p.x, p.y, e.x, e.y):
			continue
		var c := (dx * px + dy * py) / d if d > TINY else 1.0
		# Hors du cône préféré : pénalité, mais pas exclusion (on vise quand même si seul).
		var angle_penalty: float = 1.0 + a.movePreference * (1.0 - c) + (a.outOfConePenalty if c < cos_cone else 0.0)
		var score: float = (d - e.r) * angle_penalty
		if e.id == sticky:
			score -= a.stickyBonus
		if e.state == "windup":
			score -= a.threatBonus
		if D6Js.truthy(e.get("eliteMod")):
			score -= a.eliteBonus
		if score < best_score:
			best_score = score
			best = e
			best_d = d
	return {"best": best, "d": best_d}
