class_name D6FoePavois
extends RefCounted
## Portage de src/sim/foe_pavois.mjs.
## GARDE DE FACE — « Porte-pavois » (kind 'pavois'). Données : tuning.enemies.pavois.
##
## Il porte un pavois tourné vers `e.face` (angle, rad). De FACE, dans l'arc `guardArc`, les coups
## d'arme et la compétence ne portent pas (D6FoeDefense.front_blocked, lu par combat.damage_enemy) ;
## de dos et de flanc, tout passe.
##
## Machine d'états :
##   chase   — marche vers le héros et PIVOTE vers lui, lentement (turnRate rad/s) ; arme son coup
##             quand le héros est à portée ET devant lui, si un jeton de mêlée est libre.
##   windup  — face VERROUILLÉE ; télégraphe rouge en secteur (e.tele cone + area : tout le secteur
##             frappe d'un bloc à la fin de la jauge). Passer dans son dos sort du secteur.
##   recover — face toujours verrouillée, pavois ÉCARTÉ (D6FoeDefense.guard_up est faux) : fenêtre
##             de punition, de n'importe quel côté.
## L'étourdir (mur, gadget, Super) baisse le pavois et annule le coup. Aucun dégât de contact.

static var _model = null

## PAVOIS : { kind, ai: Callable(game, e, def, dt), melee }.
static func model() -> Dictionary:
	if _model == null:
		_model = {"kind": "pavois", "ai": _pavois_ai, "melee": true}
	return _model

# Portée du coup de pavois (un champion, plus gros, frappe plus loin : comme la Brute).
static func _bash_range(game: Dictionary, e: Dictionary, def: Dictionary) -> float:
	return def.bashRange * (game.tuning.elite.sizeMult if D6Js.truthy(e.eliteMod) else 1.0)

static func _chase(game: Dictionary, e: Dictionary, def: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	# Il pivote vers le héros, jamais plus vite que turnRate : un dash le prend de vitesse.
	var want: float = D6Trig.atan2(tp.dy, tp.dx)
	var turn: float = def.turnRate * dt
	e.face += D6Geo.clampv(D6Geo.angle_diff(e.face, want), -turn, turn)
	var facing: bool = absf(D6Geo.angle_diff(e.face, want)) <= def.bashArc / 2.0
	if tp.d < def.attackRange + p.r and facing and e.cooldown <= 0.0 and D6AiCommon.active_attackers(game) < game.tuning.combat.maxAttackers:
		D6AiCommon.set_state(e, "windup")
		e.atkId = D6State.new_id(game)
		return
	D6AiCommon.steer(game, e, p.x, p.y, D6AiCommon.speed_of(game, e, def))

static func _windup(game: Dictionary, e: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = game.player
	var w := D6AiCommon.windup_of(game, e, def.windup)
	var bash_range := _bash_range(game, e, def)
	e.tele = {"shape": "cone", "area": true, "angle": e.face, "range": bash_range, "arc": def.bashArc, "progress": e.stateTime / w}
	if e.stateTime < w:
		return
	e.tele = null
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})
	if D6Geo.in_sector(p.x, p.y, e.x, e.y, bash_range, e.face, def.bashArc, p.r):
		D6Combat.damage_player(game, def.damage * e.dmgScale, {"kind": "pavois", "id": e.atkId, "x": e.x, "y": e.y})
	D6AiCommon.set_state(e, "recover")

static func _pavois_ai(game: Dictionary, e: Dictionary, def: Dictionary, dt: float) -> void:
	if e.get("face") == null:
		# Première image : il fait face au héros.
		var tp := D6AiCommon.to_player(game, e)
		e.face = D6Trig.atan2(tp.dy, tp.dx)
	match e.state:
		"chase":
			_chase(game, e, def, dt)
		"windup":
			_windup(game, e, def)
		"recover":
			if e.stateTime >= def.recover:
				D6AiCommon.set_state(e, "chase")
				e.cooldown = def.cooldown
		_:
			D6AiCommon.set_state(e, "chase")
