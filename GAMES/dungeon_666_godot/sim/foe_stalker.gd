class_name D6FoeStalker
extends RefCounted
## Portage de src/sim/foe_stalker.mjs.
## EMBUSCADE — « Traqueur » (kind 'stalker'). Données : tuning.enemies.stalker.
##
## Machine d'états :
##   chase   — rôde à distance (keepDistance) ; quand sa recharge est finie, que le héros est à
##             moins de `stalkRange` et qu'un jeton de mêlée est libre, il se dissout.
##   fade    — immobile, il se dissout (`fade` s) : encore visible et VULNÉRABLE. Le tuer ou
##             l'étourdir ici annule l'embuscade.
##   ambush  — disparu `hiddenTime` s : e.hidden = true et e.spawnT > 0 (comme une apparition en
##             attente : ni ciblable, ni touchable, son IA ne tourne pas). À la première image où il
##             revient, il se pose DANS LE DOS du héros (à `backDist`, à l'opposé de player.facing ;
##             si le point est dans un mur, on essaie les écarts `backAngles`), et sa frappe est
##             télégraphiée : cercle rouge de `slashRadius` autour de lui pendant `slashWindup` s.
##   windup  — il tient la pose pendant le télégraphe (zone liée à lui : le tuer ou l'étourdir
##             l'annule, projectiles), puis la zone frappe.
##   recover — longue récupération (fenêtre de punition), puis recharge et retour en chase.
## Il garde son jeton de mêlée de la dissolution à la frappe (D6AiCommon.active_attackers).
## Aucun dégât de contact : seul le cercle télégraphié blesse.

const CLEARANCE := 2.0 # u libres autour du corps au point de réapparition

static var _model = null

## STALKER : { kind, ai: Callable(game, e, def, dt), melee }.
static func model() -> Dictionary:
	if _model == null:
		_model = {"kind": "stalker", "ai": _stalker_ai, "melee": true}
	return _model

## Point de réapparition : dans le dos du héros ; à défaut de place, sur son flanc ; sinon sur place.
static func ambush_point(game: Dictionary, e: Dictionary, def: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	for off in def.backAngles:
		var a: float = p.facing + PI + off
		var x: float = p.x + D6Trig.cos(a) * def.backDist
		var y: float = p.y + D6Trig.sin(a) * def.backDist
		if not D6Physics.point_blocked(game.room, x, y, e.r + CLEARANCE):
			return {"x": x, "y": y}
	return {"x": e.x, "y": e.y}

# Il resurgit et arme sa frappe : cercle rouge télégraphié autour de lui.
static func _reappear(game: Dictionary, e: Dictionary, def: Dictionary) -> void:
	var pt := ambush_point(game, e, def)
	e.x = pt.x
	e.y = pt.y
	e.kvx = 0.0
	e.kvy = 0.0
	e.hidden = false
	D6AiCommon.set_state(e, "windup")
	D6Combat.spawn_hazard(game, {
		"shape": "circle", "x": e.x, "y": e.y, "r": def.slashRadius * (game.tuning.elite.sizeMult if D6Js.truthy(e.eliteMod) else 1.0),
		"delay": D6AiCommon.windup_of(game, e, def.slashWindup), "damage": def.damage * e.dmgScale, "kind": "stalker", "sourceId": e.id,
	})
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})

static func _stalker_ai(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	match e.state:
		"chase":
			var tp := D6AiCommon.to_player(game, e)
			if e.cooldown <= 0.0 and tp.d < def.stalkRange and D6AiCommon.active_attackers(game) < game.tuning.combat.maxAttackers:
				D6AiCommon.set_state(e, "fade")
				return
			D6AiCommon.keep_distance(game, e, def, tp, D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y), D6AiCommon.speed_of(game, e, def))
		"fade":
			if e.stateTime >= def.fade:
				D6AiCommon.set_state(e, "ambush")
				e.hidden = true
				e.spawnT = def.hiddenTime # disparu : enemies ne relance son IA qu'à son retour
		"ambush":
			_reappear(game, e, def)
		"windup":
			if e.stateTime >= D6AiCommon.windup_of(game, e, def.slashWindup):
				D6AiCommon.set_state(e, "recover")
		"recover":
			if e.stateTime >= def.recover:
				D6AiCommon.set_state(e, "chase")
				e.cooldown = def.cooldown * D6Rng.rand_range(game.rng.ai, def.cooldownJitter[0], def.cooldownJitter[1])
		_:
			D6AiCommon.set_state(e, "chase")
