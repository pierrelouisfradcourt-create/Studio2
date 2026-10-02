class_name D6AiCommon
extends RefCounted
## Portage de src/sim/ai_common.mjs.
## Briques d'IA partagées par tous les archétypes d'ennemis (module feuille : n'importe pas
## enemies, pour que chaque archétype vive dans son propre fichier sans import circulaire).
## `emit` est réexporté par le module JavaScript : ici on appelle directement D6State.emit.

# Archétypes qui prennent un JETON D'ATTAQUE de mêlée (au plus combat.maxAttackers à la fois).
# Ensemble MODIFIÉ au chargement de D6Enemies (les archétypes ajoutés s'y inscrivent) : copie de
# la table partagée, jamais la table elle-même.
static var _melee_kinds = null
# Archétypes qui prennent un jeton de TIR (au plus combat.maxShooters à la fois).
static var _shooter_kinds = null

# États où un ennemi de mêlée TIENT son jeton d'attaque. « fade » et « ambush » : le Traqueur
# garde le sien de sa dissolution à sa frappe (foe_stalker), sinon il resurgirait en surnombre.
const TOKEN_STATES := ["windup", "strike", "charge", "fade", "ambush"]

# Recharge de l'archer : ×0,85 à ×1,25. Les archétypes ajoutés portent la leur en données (cooldownJitter).
const ARCHER_KIND := "archer"
const ARCHER_JITTER := [0.85, 1.25]

# Objet partagé de module (const navOut = { x: 0, y: 0 }).
static var _nav_out: Dictionary = {"x": 0.0, "y": 0.0}

## MELEE_KINDS (ensemble tenu en tableau ; l'ordre n'a pas de sens).
static func melee_kinds() -> Array:
	if _melee_kinds == null:
		_melee_kinds = (D6Data.tables().ai_common.MELEE_KINDS as Array).duplicate()
	return _melee_kinds

## SHOOTER_KINDS (ensemble tenu en tableau ; l'ordre n'a pas de sens).
static func shooter_kinds() -> Array:
	if _shooter_kinds == null:
		_shooter_kinds = (D6Data.tables().ai_common.SHOOTER_KINDS as Array).duplicate()
	return _shooter_kinds

static func speed_of(game: Dictionary, e: Dictionary, def: Dictionary) -> float:
	var s: float = def.speed
	if e.eliteMod == "rapide":
		s *= game.tuning.elite.mods.rapide.speedMult
	if e.chill > 0.0:
		s *= e.chillMult
	return s

static func windup_of(game: Dictionary, e: Dictionary, base: float) -> float:
	if e.eliteMod == "rapide":
		return base * game.tuning.elite.mods.rapide.windupMult
	return base

static func active_attackers(game: Dictionary) -> float:
	var kinds := melee_kinds()
	var n := 0.0
	for o in game.enemies:
		if not o.dead and kinds.has(o.kind) and TOKEN_STATES.has(o.state):
			n += 1.0
	return n

static func active_shooters(game: Dictionary) -> float:
	var kinds := shooter_kinds()
	var n := 0.0
	for o in game.enemies:
		if not o.dead and kinds.has(o.kind) and o.state == "windup":
			n += 1.0
	return n

static func set_state(e: Dictionary, s: String) -> void:
	e.state = s
	e.stateTime = 0.0

## Recharge d'un ennemi qui sort de sa récupération : def.cooldown, variée par def.cooldownJitter
## ([min, max], un tirage dans game.rng.ai) pour les archétypes qui ne doivent pas être des métronomes.
static func recharge_of(game: Dictionary, e: Dictionary, def: Dictionary) -> float:
	var jitter = def.get("cooldownJitter")
	if jitter == null and e.kind == ARCHER_KIND:
		jitter = ARCHER_JITTER
	if jitter == null:
		return def.cooldown
	return def.cooldown * D6Rng.rand_range(game.rng.ai, jitter[0], jitter[1])

## Étourdit un ennemi `duration` s (l'appelant a déjà écarté Gardiens et ennemis en garde) : son
## attaque en cours est annulée. S'il RÉCUPÉRAIT de son attaque, ce qu'il lui restait à attendre
## avant de pouvoir ré-attaquer (fin de la récupération, puis recharge) passe dans sa recharge,
## qui court pendant l'étourdissement : étourdir ne raccourcit jamais ce délai.
static func stun(game: Dictionary, e: Dictionary, duration: float) -> void:
	var def = game.tuning.enemies.get(e.kind)
	if e.state == "recover" and def is Dictionary and def.get("recover") != null:
		e.cooldown = maxf(e.cooldown, maxf(0.0, def.recover - e.stateTime) + recharge_of(game, e, def))
	e.stun = maxf(e.stun, duration)
	e.tele = null
	set_state(e, "stunned")

static func to_player(game: Dictionary, e: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var d: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	return {"dx": dx / d, "dy": dy / d, "d": d}

## Se dirige vers (x, y) ; sans ligne de vue, suit le champ de navigation (contourne).
static func steer(game: Dictionary, e: Dictionary, x: float, y: float, speed: float) -> void:
	var dx: float = x - e.x
	var dy: float = y - e.y
	var d: float = sqrt(dx * dx + dy * dy)
	if d < 4.0:
		return
	if not D6Physics.line_of_sight(game.room, e.x, e.y, x, y) and D6Nav.nav_direction(game, e.x, e.y, _nav_out):
		e.vx = _nav_out.x * speed
		e.vy = _nav_out.y * speed
		return
	e.vx = (dx / d) * speed
	e.vy = (dy / d) * speed

## Fait suivre la direction visée jusqu'au verrouillage, puis la fige (équité).
static func track_until_lock(game: Dictionary, e: Dictionary, lock_fraction: float, windup: float) -> void:
	if e.stateTime < windup * lock_fraction:
		var tp := to_player(game, e)
		e.dirX = tp.dx
		e.dirY = tp.dy

## Nombre d'ennemis vivants d'un archétype (plafonds d'invocation, etc.).
static func count_alive(game: Dictionary, kind) -> float:
	var n := 0.0
	for o in game.enemies:
		if not o.dead and o.kind == kind:
			n += 1.0
	return n

# ---------------------------------------------------------------- tireurs à distance

## Garde ses distances (archétypes à distance : zone, invocateur) : fuit sous `def.fleeDist`,
## se rapproche au-delà de `def.preferredDist + def.approachSlack` ou sans ligne de vue, sinon
## tourne autour du héros (`def.strafeMult` de la vitesse ; change parfois de sens, avec la
## probabilité `def.strafeFlip` par image). Le comportement de l'archer, mis en données.
static func keep_distance(game: Dictionary, e: Dictionary, def: Dictionary, tp: Dictionary, sees: bool, speed: float) -> void:
	# On ne fuit que ce qu'on voit : derrière un obstacle, fuite et approche s'annulaient à chaque
	# image et le tireur, vibrant sur place, n'attaquait plus jamais.
	if tp.d < def.fleeDist and sees:
		e.vx = -tp.dx * speed
		e.vy = -tp.dy * speed
	elif tp.d > def.preferredDist + def.approachSlack or not sees:
		steer(game, e, game.player.x, game.player.y, speed)
	else:
		e.vx = -tp.dy * speed * def.strafeMult * e.strafe
		e.vy = tp.dx * speed * def.strafeMult * e.strafe
		if D6Rng.rand(game.rng.ai) < def.strafeFlip:
			e.strafe = -e.strafe

# ---------------------------------------------------------------- invocations

## Invocations en cours dans la salle : vivantes (hors boss) + cercles d'invocation en attente.
static func summoned_count(game: Dictionary) -> float:
	var n := 0.0
	for o in game.enemies:
		if not o.dead and D6Js.truthy(o.get("summoned")) and not D6Js.truthy(o.get("boss")):
			n += 1.0
	for s in game.spawns:
		if D6Js.truthy(s.get("summoned")):
			n += 1.0
	return n

## Plafond d'invocations VIVANTES de la salle : somme des plafonds des invocateurs vivants
## (archétype : tuning.enemies[kind].maxMinions ; élite : tuning.elite.mods[mod].maxMinions).
## Un invocateur mort ne compte plus : ses invocations restent, mais plus rien ne s'y ajoute.
static func summon_cap(game: Dictionary) -> float:
	var t: Dictionary = game.tuning
	var cap := 0.0
	for o in game.enemies:
		if o.dead or D6Js.truthy(o.get("boss")):
			continue
		var def = t.enemies.get(o.kind)
		if def != null:
			cap += D6Js.nz(def.get("maxMinions"), 0.0)
		var mod = o.get("eliteMod")
		if D6Js.truthy(mod):
			var m = t.elite.mods.get(mod)
			if m != null:
				cap += D6Js.nz(m.get("maxMinions"), 0.0)
	return cap

## Places libres sous le plafond d'invocations de la salle.
static func summon_room(game: Dictionary) -> float:
	return maxf(0.0, summon_cap(game) - summoned_count(game))

## Ouvre jusqu'à `count` cercles d'invocation (queueSpawn : visibles `room.spawnWarn` s avant
## l'apparition, jamais sous les pieds du héros) autour de `e`. Rend le nombre de cercles ouverts.
static func summon_around(game: Dictionary, e: Dictionary, kind, count: float, min_r: float, max_r: float, min_player_dist: float) -> float:
	var r: float = game.tuning.enemies[kind].radius
	var n := 0.0
	var i := 0.0
	while i < count:
		i += 1.0
		var pt = D6Spawns.find_spawn_point(game, r, min_player_dist, {"x": e.x, "y": e.y, "minR": e.r + min_r, "maxR": e.r + max_r})
		if pt == null:
			continue
		D6Spawns.queue_spawn(game, kind, pt.x, pt.y, {"summoned": true})
		n += 1.0
	return n
