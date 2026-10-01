class_name D6FoePyromancer
extends RefCounted
## Portage de src/sim/foe_pyromancer.mjs.
## ENNEMI DE ZONE — « Pyromancienne » (kind 'pyromancer'). Données : tuning.enemies.pyromancer.
##
## Machine d'états :
##   chase   — garde ses distances (fuit, se rapproche, tourne autour : keepDistance) ;
##             incante quand elle voit le héros, à portée, et qu'un jeton de TIR est libre.
##   windup  — bâton levé (castTime, lisible sur elle), puis pose `pyre.count` cercles de feu
##             TÉLÉGRAPHIÉS (rouge = ça fait mal) : un sur le héros, les autres répartis autour.
##             Elle tient le sort jusqu'à l'allumage du dernier cercle (le jeton de tir reste
##             pris) : la tuer ou l'étourdir avant ANNULE les cercles (sourceId, projectiles).
##   recover — souffle, puis repart en chase (temps de recharge).
## Chaque cercle allumé laisse une FLAQUE brûlante persistante et visible (`linger` s) qui ne
## blesse qu'à l'intérieur, par ticks (projectiles, updateHazards). Aucun dégât de contact.

static var _model = null

## PYROMANCER : { kind, ai: Callable(game, e, def, dt), shooter }.
static func model() -> Dictionary:
	if _model == null:
		_model = {"kind": "pyromancer", "ai": _pyromancer_ai, "shooter": true}
	return _model

## Fin du sort : le dernier cercle s'allume `pyreSpan` s après son apparition.
static func pyre_span(def: Dictionary) -> float:
	return def.pyre.delay + (def.pyre.count - 1.0) * def.pyre.stagger

## Pose UN cercle de feu télégraphié (`delay` s) qui laisse une flaque brûlante. Le centre reste
## dans la salle, à au moins un demi-rayon des murs (la flaque se voit sur le sol, pas dans le
## mur). `source` : l'ennemi qui l'a lancé (sa mort ou son étourdissement l'annulent pendant le
## télégraphe), ou null.
static func spawn_pyre(game: Dictionary, x: float, y: float, def: Dictionary, source, delay: float):
	var room: Dictionary = game.room
	var pyre: Dictionary = def.pyre
	var scale: float = source.dmgScale if source != null else 1.0
	var lo: float = room.pad + pyre.radius * pyre.wallInset
	return D6Combat.spawn_hazard(game, {
		"shape": "circle",
		"x": D6Geo.clampv(x, lo, room.w - lo),
		"y": D6Geo.clampv(y, lo, room.h - lo),
		"r": pyre.radius,
		"delay": delay,
		"damage": def.damage * scale,
		"kind": "pyre",
		"sourceId": source.id if source != null else 0.0,
		"linger": pyre.linger,
		"tickEvery": pyre.tickEvery,
		"tickDamage": pyre.tickDamage * scale,
	})

## Un cercle sur le héros, les satellites répartis régulièrement autour (angle de départ tiré).
static func _cast_pyres(game: Dictionary, e: Dictionary, def: Dictionary) -> void:
	var p: Dictionary = game.player
	var pyre: Dictionary = def.pyre
	spawn_pyre(game, p.x, p.y, def, e, pyre.delay)
	var sats: float = pyre.count - 1.0
	var a0: float = D6Rng.rand(game.rng.ai) * TAU
	var i := 0.0
	while i < sats:
		var a: float = a0 + (i / sats) * TAU
		spawn_pyre(game, p.x + D6Trig.cos(a) * pyre.spread, p.y + D6Trig.sin(a) * pyre.spread, def, e, pyre.delay + (i + 1.0) * pyre.stagger)
		i += 1.0

static func _pyromancer_ai(game: Dictionary, e: Dictionary, def: Dictionary, _dt = null) -> void:
	var p: Dictionary = game.player
	var tp := D6AiCommon.to_player(game, e)
	match e.state:
		"chase":
			var sees: bool = D6Physics.line_of_sight(game.room, e.x, e.y, p.x, p.y)
			if e.cooldown <= 0.0 and sees and tp.d < def.castRange and D6AiCommon.active_shooters(game) < game.tuning.combat.maxShooters:
				D6AiCommon.set_state(e, "windup")
				e.castDone = false
				return
			D6AiCommon.keep_distance(game, e, def, tp, sees, D6AiCommon.speed_of(game, e, def))
		"windup":
			var cast := D6AiCommon.windup_of(game, e, def.castTime)
			if not D6Js.truthy(e.get("castDone")) and e.stateTime >= cast:
				e.castDone = true
				_cast_pyres(game, e, def)
				D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": e.kind})
			if D6Js.truthy(e.get("castDone")) and e.stateTime >= cast + pyre_span(def):
				D6AiCommon.set_state(e, "recover")
		"recover":
			if e.stateTime >= def.recover:
				D6AiCommon.set_state(e, "chase")
				# Le temps de recharge varie (def.cooldownJitter) : pas de métronome.
				e.cooldown = def.cooldown * D6Rng.rand_range(game.rng.ai, def.cooldownJitter[0], def.cooldownJitter[1])
		_:
			D6AiCommon.set_state(e, "chase")
