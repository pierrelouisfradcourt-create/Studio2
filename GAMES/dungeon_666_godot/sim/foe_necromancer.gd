class_name D6FoeNecromancer
extends RefCounted
## Portage de src/sim/foe_necromancer.mjs.
## INVOCATEUR — « Nécromancien » (kind 'necromancer'). Données : tuning.enemies.necromancer.
##
## Machine d'états :
##   chase   — garde ses distances et FUIT le héros (plus vite quand il est talonné) ; canalise
##             quand le héros est assez loin et qu'il reste de la place sous le plafond
##             d'invocations de la salle (ai_common.summonRoom).
##   channel — immobile, alerte violette INOFFENSIVE autour de lui (e.tele harmless: true) ;
##             à la fin, ouvre des cercles d'invocation (queueSpawn) d'où sortent des diablotins
##             (invocations : ni or ni Âmes). Le tuer ou l'étourdir pendant la canalisation
##             l'annule : aucun cercle ne s'ouvre.
##   recover — souffle, puis repart (temps de recharge).
## Il n'attaque jamais lui-même : peu de PV, cible prioritaire. Aucun dégât de contact.

static var _model = null

## NECROMANCER : { kind, ai: Callable(game, e, def, dt) }.
static func model() -> Dictionary:
	if _model == null:
		_model = {"kind": "necromancer", "ai": _necromancer_ai}
	return _model

static func _necromancer_ai(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	match e.state:
		"chase":
			if e.cooldown <= 0.0 and tp.d > def.fleeDist and D6AiCommon.summon_room(game) > 0.0:
				D6AiCommon.set_state(e, "channel")
				e.tele = {"shape": "circle", "r": def.channelRadius, "progress": 0.0, "harmless": true} # visible dès la 1re image
				D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})
				return
			var sees: bool = D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y)
			var flee: float = def.fleeSpeedMult if tp.d < def.fleeDist else 1.0
			D6AiCommon.keep_distance(game, e, def, tp, sees, D6AiCommon.speed_of(game, e, def) * flee)
		"channel":
			var ch := D6AiCommon.windup_of(game, e, def.channel)
			e.tele = {"shape": "circle", "r": def.channelRadius, "progress": e.stateTime / ch, "harmless": true}
			if e.stateTime >= ch:
				e.tele = null
				var n: float = minf(def.count, D6AiCommon.summon_room(game))
				D6AiCommon.summon_around(game, e, def.minionKind, n, def.summonMinR, def.summonMaxR, def.summonMinPlayerDist)
				D6AiCommon.set_state(e, "recover")
		"recover":
			if e.stateTime >= def.recover:
				D6AiCommon.set_state(e, "chase")
				e.cooldown = D6AiCommon.recharge_of(game, e, def)
		_:
			D6AiCommon.set_state(e, "chase")
