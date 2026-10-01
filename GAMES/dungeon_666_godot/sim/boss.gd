class_name D6Boss
extends RefCounted
## Portage de src/sim/boss.mjs.
## MOTEUR DES GARDIENS (boss de fin de section, tous les 18 étages).
## Commun à tous les modèles : trois phases (seuils de PV en tuning), transitions invulnérables
## (projectiles effacés, renforts, orbe de soin), repos entre deux patterns (fenêtre de
## punition), patterns jamais répétés deux fois de suite, télégraphes JAMAIS raccourcis.
## Chaque modèle (sim/boss_<modèle>.gd) fournit ses patterns et leur ordre par phase.

static var _models = null

## Registre des modèles de Gardien (BOSS_MODELS) : { byPhase: {"1": [...], "2": [...], "3": [...]},
## patterns: {nom: Callable}, rest?(game, e, d, dt, speed), tick?(game, e, d, dt),
## available?(game, e, d, nom), onPhase?(game, e, d) }. La clé est le `kind` de l'ennemi
## (= clé de tuning.boss).
##   tick      — appelé à chaque pas, quel que soit le pattern (zones persistantes, bouclier) ;
##   available — filtre les patterns utilisables maintenant (ex. pas de nouveaux renforts tant que
##               les précédents vivent) ;
##   onPhase   — appelé au changement de phase, APRÈS l'effacement des menaces : le modèle y
##               éteint ce qu'il rejouerait lui-même (ex. braises qui pulsent).
## Un modèle sans ces crochets (Charon) n'en voit aucun effet.
## Construit une fois, PARTAGÉ : ne pas le modifier.
static func boss_models() -> Dictionary:
	if _models == null:
		var m := {"gardien": D6BossCharon.model()}
		m.merge(D6BossModels.extra_boss_models(), true)
		_models = m
	return _models

static func _model_of(e: Dictionary) -> Dictionary:
	var m = boss_models().get(e.kind)
	return D6BossCharon.model() if m == null else m

static func _next_pattern(game: Dictionary, e: Dictionary) -> void:
	var model := _model_of(e)
	var list: Array = model.byPhase[D6Js.num_str(e.phase)]
	if model.has("available"):
		var d := D6BossCommon.boss_def(game, e)
		var available: Callable = model.available
		var usable: Array = list.filter(func(name): return D6Js.truthy(available.call(game, e, d, name)))
		if usable.size() > 0:
			list = usable
	var choice = D6Rng.pick(game.rng.ai, list)
	# Jamais deux fois de suite le même pattern.
	var previous = e.get("pattern")
	var i := 0
	while i < 4 and previous is String and choice == previous:
		choice = D6Rng.pick(game.rng.ai, list)
		i += 1
	e.pattern = choice
	e.secondCharge = false
	D6BossCommon.set_state(e, choice)

## Changement de phase : invulnérable un instant, projectiles effacés, renforts, orbe de soin.
static func _enter_phase(game: Dictionary, e: Dictionary, d: Dictionary) -> void:
	e.phase += 1
	e.tele = null
	e.invuln = d.transition
	for pr in game.projectiles:
		if pr.get("owner") == "enemy":
			pr.dead = true
	for h in game.hazards:
		if D6Js.truthy(h.get("hitsPlayer")):
			h.done = true
	var model := _model_of(e)
	if model.has("onPhase"):
		model.onPhase.call(game, e, d)
	var kinds = d.reinforcements.get(D6Js.num_str(e.phase))
	if kinds != null:
		for kind in kinds:
			var pt = D6Spawns.find_spawn_point(game, 14.0, 180.0, {"x": e.x, "y": e.y, "minR": e.r + 60.0, "maxR": e.r + 260.0})
			if pt != null:
				D6Spawns.queue_spawn(game, kind, pt.x, pt.y, {"summoned": true})
	D6Combat.spawn_pickup(game, "heal", e.x, e.y + e.r + 30.0, d.phaseHealOrb)
	D6State.emit(game, "bossPhase", {"id": e.id, "x": e.x, "y": e.y, "phase": e.phase})
	D6BossCommon.set_state(e, "roar")
	e.restFor = d.transition

static func update_boss(game: Dictionary, e: Dictionary, dt: float) -> void:
	var d := D6BossCommon.boss_def(game, e)
	var model := _model_of(e)
	e.invuln = maxf(0.0, float(D6Js.nz(e.get("invuln"), 0.0)) - dt)
	# Point faible exposé (boss_common.expose) : décompté sur l'horloge du Gardien (figé avec lui).
	if float(D6Js.nz(e.get("exposed"), 0.0)) > 0.0:
		e.exposed = maxf(0.0, e.exposed - dt)
		D6BossCommon.hold_vuln_flag(e)
	if model.has("tick"):
		model.tick.call(game, e, d, dt)
	var threshold: float = d.phase2At if e.phase == 1 else (d.phase3At if e.phase == 2 else -1.0)
	if threshold > 0.0 and e.hp <= e.maxHp * threshold:
		_enter_phase(game, e, d)
		return
	var speed: float = d.speed * d.speedMultByPhase[int(e.phase) - 1]
	match e.state:
		"roar":
			var rest_for = e.get("restFor")
			if rest_for != null and e.stateTime >= rest_for:
				e.restFor = null
				_next_pattern(game, e)
		"chase", "rest":
			_rest(game, e, d, model, dt, speed)
		"stunned":
			pass
		_:
			var fn = model.patterns.get(e.state)
			if fn != null:
				fn.call(game, e, d, dt, speed)
			else:
				D6BossCommon.set_state(e, "rest")

## États 'chase' et 'rest' : le Gardien souffle (durée tirée une fois), puis choisit un pattern.
## `e.restFor = undefined` du JavaScript : null ici (clé absente à la naissance, donc `.get`).
static func _rest(game: Dictionary, e: Dictionary, d: Dictionary, model: Dictionary, dt: float, speed: float) -> void:
	if e.get("restFor") == null:
		e.restFor = D6Rng.rand_range(game.rng.ai, d.restBetween[0], d.restBetween[1]) * d.restMultByPhase[int(e.phase) - 1]
	if model.has("rest"):
		model.rest.call(game, e, d, dt, speed)
	else:
		var tp := D6BossCommon.to_player(game, e)
		if tp.d > 160.0:
			e.vx = tp.dx * speed
			e.vy = tp.dy * speed
	if e.stateTime >= e.restFor:
		e.restFor = null
		_next_pattern(game, e)
