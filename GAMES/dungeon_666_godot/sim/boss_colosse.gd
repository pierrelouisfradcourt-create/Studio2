class_name D6BossColosse
extends RefCounted
## Portage de src/sim/boss_colosse.mjs.
## Gardien « Éphialte, le Colosse enchaîné » (modèle `colosse`, section 4 — fin du 1er Cercle —
## puis en rotation). Géant LENT et massif : chaque coup est énorme mais lisible de loin ; il
## RÉTRÉCIT l'arène (braises persistantes) et se protège derrière ses geôliers. Patterns :
##   poing    — coups de poing en ligne (1 / 2 / 3 selon la phase), chacun visé là où se tient le
##              héros ; après le dernier, le bras reste coincé : POINT FAIBLE exposé (dégâts majorés).
##   seisme   — ondes concentriques (un cercle puis des anneaux) qui partent de lui l'une après
##              l'autre : entrer dans l'onde déjà passée (vers lui !) ou dasher à travers.
##   eboulis  — rochers télégraphiés autour du héros (l'un tombe sur lui) ; dès la phase 2, chaque
##              rocher laisse une BRAISE qui pulse (cercle rejoué, durée bornée) : l'arène rétrécit.
##   geoliers — (phase 2+, UNE fois par phase : geoliers.callsPerPhase) il appelle ses geôliers
##              (archers) ; tant qu'ils vivent, ses chaînes le rendent INVULNÉRABLE (bouclier
##              visible, borné dans le temps) : les adds d'abord.
## Changement de phase : les braises s'éteignent avec les autres zones (crochet onPhase).
##
## Le moteur appelle tout pattern avec (game, e, d, dt, speed), JavaScript ignorant les arguments
## en trop : les fonctions qui en déclarent moins reçoivent ici des arguments de queue inutilisés.

static var _model = null

## Grondement d'effort : le son porte le timbre du Gardien (recipes.mjs, ENEMY_ATTACK.colosse).
static func _grunt(game: Dictionary, e: Dictionary) -> void:
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "colosse"})

# ---------------------------------------------------------------- poing

static func poing(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var f: Dictionary = d.poing
	D6BossCommon.hold_still(e)
	var fists: float = f.fistsByPhase[int(e.phase) - 1]
	if e.get("sub") == "recover":
		D6BossCommon.exposed_recovery(game, e, f.stuck, f.exposedMult, dt)
		return
	e.subT += dt
	# Poing k posé à k × fistGap, visé sur le héros À CET INSTANT, télégraphié `windup` s.
	while e.patternStep < fists and e.subT >= e.patternStep * f.fistGap:
		var tp := D6BossCommon.to_player(game, e)
		D6BossCommon.boss_hazard(game, e, {
			"shape": "line", "x": e.x, "y": e.y, "angle": D6Trig.atan2(tp.dy, tp.dx), "length": e.r + f.length, "width": f.width,
			"delay": f.windup, "damage": f.damage, "kind": "colosseFist",
		})
		e.patternStep += 1
		_grunt(game, e)
	# Le dernier poing frappe : le bras reste coincé dans le sol.
	if e.subT >= (fists - 1.0) * f.fistGap + f.windup:
		D6BossCommon.exposed_recovery(game, e, f.stuck, f.exposedMult, 0.0)

# ---------------------------------------------------------------- séisme

static func seisme(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var q: Dictionary = d.seisme
	D6BossCommon.hold_still(e)
	var rings: float = q.ringsByPhase[int(e.phase) - 1]
	if not D6Js.truthy(e.get("sub")):
		var k := 0.0
		while k < rings:
			var delay: float = q.delay + k * q.step
			if k == 0.0:
				D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": e.x, "y": e.y, "r": q.band, "delay": delay, "damage": q.damage, "kind": "colosseQuake"})
			else:
				D6BossCommon.boss_hazard(game, e, {"shape": "ring", "x": e.x, "y": e.y, "r": (k + 1.0) * q.band, "inner": k * q.band, "delay": delay, "damage": q.damage, "kind": "colosseQuake"})
			k += 1.0
		D6BossCommon.set_sub(e, "quake")
		_grunt(game, e)
	e.subT += dt
	if e.subT >= q.delay + (rings - 1.0) * q.step:
		D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- éboulis

static func eboulis(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var b: Dictionary = d.eboulis
	D6BossCommon.hold_still(e)
	if not D6Js.truthy(e.get("sub")):
		var room: Dictionary = game.room
		var p: Dictionary = game.player
		var rocks: float = b.rocksByPhase[int(e.phase) - 1]
		var last := 0.0
		var k := 0.0
		while k < rocks:
			# Le premier tombe sur le héros ; les autres autour de lui (tirage uniforme dans le disque).
			var a := D6Rng.rand(game.rng.ai) * TAU
			var rr: float = 0.0 if k == 0.0 else b.spread * sqrt(D6Rng.rand(game.rng.ai))
			var x := D6Geo.clampv(p.x + D6Trig.cos(a) * rr, room.pad + b.radius / 2.0, room.w - room.pad - b.radius / 2.0)
			var y := D6Geo.clampv(p.y + D6Trig.sin(a) * rr, room.pad + b.radius / 2.0, room.h - room.pad - b.radius / 2.0)
			var delay: float = b.delayMin + D6Rng.rand(game.rng.ai) * (b.delayMax - b.delayMin)
			last = maxf(last, delay)
			var rock = D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": x, "y": y, "r": b.radius, "delay": delay, "damage": b.damage, "kind": "colosseRock"})
			if e.phase >= b.poolFromPhase:
				_add_pool(e, b, rock)
			k += 1.0
		e.rockEnd = last
		D6BossCommon.set_sub(e, "fall")
		_grunt(game, e)
	e.subT += dt
	if e.subT >= e.rockEnd:
		D6BossCommon.to_rest(game, e)

# ---------------------------------------------------------------- braises (zones persistantes)

## Braise promise par un rocher : elle s'allume quand il tombe VRAIMENT, puis pulse poolLife s.
## `rock` est LE dictionnaire de la zone (celui de game.hazards) : la braise le suit par référence.
static func _add_pool(e: Dictionary, b: Dictionary, rock: Dictionary) -> void:
	if e.get("pools") == null:
		e.pools = []
	e.pools.append({"x": rock.x, "y": rock.y, "rock": rock, "end": INF, "h": null})
	# Au plus `poolMax` braises : la plus ancienne s'éteint (l'arène rétrécit, sans jamais se fermer).
	while e.pools.size() > b.poolMax:
		e.pools.pop_front()

## Chaque braise active rejoue un cercle télégraphié de `poolPulse` s tant qu'elle brûle.
static func _tick_pools(game: Dictionary, e: Dictionary, b: Dictionary) -> void:
	var pools = e.get("pools")
	if pools == null or pools.size() == 0:
		return
	var w := 0
	var count: int = pools.size()
	for idx in range(count):
		var pool: Dictionary = pools[idx]
		if pool.rock != null:
			# Rocher annulé (transition de phase) : pas de braise. Encore en l'air : on attend.
			if not D6Js.truthy(pool.rock.get("done")):
				pools[w] = pool
				w += 1
				continue
			if pool.rock.t < pool.rock.delay:
				continue
			pool.rock = null
			pool.end = game.time + b.poolLife
		if game.time >= pool.end:
			continue
		pools[w] = pool
		w += 1
		if pool.h == null or D6Js.truthy(pool.h.get("done")):
			pool.h = D6BossCommon.boss_hazard(game, e, {"shape": "circle", "x": pool.x, "y": pool.y, "r": b.poolRadius, "delay": b.poolPulse, "damage": b.poolDamage, "kind": "colosseEmber"})
	pools.resize(w)

# ---------------------------------------------------------------- geôliers et bouclier

static func geoliers(game: Dictionary, e: Dictionary, d: Dictionary, dt: float, _speed: float = 0.0) -> void:
	var g: Dictionary = d.geoliers
	D6BossCommon.hold_still(e)
	if not D6Js.truthy(e.get("sub")):
		D6BossCommon.set_sub(e, "call")
	e.subT += dt
	if e.sub == "call":
		# Appel : alerte INOFFENSIVE (violette), comme toute invocation.
		e.tele = {"shape": "circle", "r": e.r + g.telePad, "progress": e.subT / g.windup, "harmless": true}
		if e.subT < g.windup:
			return
		e.tele = null
		if _call_jailers(game, e, g) > 0.0:
			_raise_shield(game, e, g)
		D6BossCommon.set_sub(e, "done")
	D6BossCommon.to_rest(game, e)

## Ouvre les cercles d'invocation des geôliers de la phase ; rend le nombre de geôliers appelés
## (moins que prévu, voire aucun, si la salle n'a plus de point d'apparition libre).
static func _call_jailers(game: Dictionary, e: Dictionary, g: Dictionary) -> float:
	var called := 0.0
	var count: float = g.countByPhase[int(e.phase) - 1]
	for i in range(int(count)):
		var pt = D6Spawns.find_spawn_point(game, 14.0, g.minPlayerDist, {"x": e.x, "y": e.y, "minR": e.r + g.minR, "maxR": e.r + g.maxR})
		if pt != null:
			D6Spawns.queue_spawn(game, g.kind, pt.x, pt.y, {"summoned": true})
			called += 1.0
	return called

## Des geôliers arrivent : le bouclier se lève et l'appel de la phase est compté. Un appel qui ne
## fait venir personne ne passe pas ici : il ne consomme rien, le Colosse pourra rappeler.
static func _raise_shield(game: Dictionary, e: Dictionary, g: Dictionary) -> void:
	e.shieldT = g.shieldMax
	e.shielded = true
	if e.get("jailerCalls") == null:
		e.jailerCalls = {}
	var key := D6Js.num_str(e.phase)
	e.jailerCalls[key] = e.jailerCalls.get(key, 0.0) + 1.0
	D6State.emit(game, "bossSummon", {"id": e.id, "x": e.x, "y": e.y})
	D6State.emit(game, "bossShield", {"id": e.id, "x": e.x, "y": e.y, "up": true})

## Bouclier de chaînes : tenu tant qu'un serviteur vit (et au plus shieldMax s).
static func _tick_shield(game: Dictionary, e: Dictionary, g: Dictionary, dt: float) -> void:
	if not D6Js.truthy(e.get("shielded")):
		return
	e.shieldT -= dt
	if e.shieldT > 0.0 and D6BossCommon.summoned_alive(game) > 0.0:
		e.invuln = maxf(e.invuln, g.shieldHold)
		return
	e.shielded = false
	e.shieldT = 0.0
	e.invuln = 0.0
	D6State.emit(game, "bossShield", {"id": e.id, "x": e.x, "y": e.y, "up": false})

static func _tick(game: Dictionary, e: Dictionary, d: Dictionary, dt: float) -> void:
	_tick_shield(game, e, d.geoliers, dt)
	_tick_pools(game, e, d.eboulis)

## Geôliers : au plus `callsPerPhase` appels par phase (sans quoi le bouclier se recyclerait dès
## la chute des archers et le Colosse deviendrait un sac à PV), et jamais tant que des serviteurs
## vivent ou que le bouclier tient.
static func _available(game: Dictionary, e: Dictionary, d: Dictionary, name) -> bool:
	if name != "geoliers":
		return true
	var g: Dictionary = d.geoliers
	var jailer_calls = e.get("jailerCalls")
	var calls: float = 0.0 if jailer_calls == null else jailer_calls.get(D6Js.num_str(e.phase), 0.0)
	return g.countByPhase[int(e.phase) - 1] > 0.0 and calls < g.callsPerPhase and not D6Js.truthy(e.get("shielded")) and D6BossCommon.summoned_alive(game) == 0.0

## Changement de phase : les braises s'éteignent (les zones viennent d'être effacées par le moteur).
static func _on_phase(_game: Dictionary, e: Dictionary, _d: Dictionary = {}) -> void:
	e.pools = []

## COLOSSE. Poing, séisme et éboulis d'emblée ; les geôliers (et les braises) à partir de la
## phase 2. Construit une fois, PARTAGÉ : ne pas le modifier.
static func model() -> Dictionary:
	if _model == null:
		_model = {
			"byPhase": {"1": ["poing", "seisme", "eboulis"], "2": ["poing", "seisme", "eboulis", "geoliers"], "3": ["poing", "seisme", "eboulis", "geoliers"]},
			"patterns": {"poing": poing, "seisme": seisme, "eboulis": eboulis, "geoliers": geoliers},
			"tick": _tick,
			"available": _available,
			"onPhase": _on_phase,
		}
	return _model
