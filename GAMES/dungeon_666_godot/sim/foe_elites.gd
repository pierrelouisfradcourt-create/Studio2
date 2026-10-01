class_name D6FoeElites
extends RefCounted
## Portage de src/sim/foe_elites.mjs.
## ÉLITES — modificateurs façon champions Diablo (données : tuning.elite.mods).
## Un seul modificateur par élite. Les trois d'origine sont lus là où ils agissent (rapide :
## ai_common.speedOf ; blindé : combat.damageEnemy ; ardent : combat.killEnemy). Les champions
## V2 vivent ici :
##   vampirique — chaque coup qui BLESSE le héros soigne l'élite (leech × dégâts infligés) ;
##                rayon de drain visible (e.leechFlash). Branché sur toutes les façons de
##                blesser : coup direct (enemies), zone et projectile (projectiles).
##   bouclier   — bulle d'immunité périodique (e.invuln, lu par combat.damageEnemy), annoncée
##                `warn` s à l'avance par un anneau doré inoffensif (e.modPhase 'warn').
##   invocateur — canalise (alerte violette inoffensive, e.modPhase 'channel'), puis ouvre des
##                cercles d'invocation sous le plafond de la salle. Le tuer pendant la
##                canalisation l'annule ; l'étourdir aussi.
## Module feuille côté sim (n'importe ni enemies ni projectiles).

## Modificateur d'élite pour un archétype `kind` à l'étage `info` (floorInfo). UN tirage dans
## game.rng.gen, comme avant : dans la 1re section, un modificateur n'entre qu'à partir de son
## `minIndex` (les premiers étages gardent exactement le tirage d'origine).
static func pick_elite_mod(game: Dictionary, kind, info: Dictionary):
	var mods: Dictionary = game.tuning.elite.mods
	var idx: float = INF if info.section > 1.0 else info.indexInSection
	var pool: Array = []
	for m in mods: # Object.keys : ordre d'insertion, tenu par le dictionnaire
		if D6Js.nz(mods[m].get("minIndex"), 1.0) <= idx and not (D6Js.nz(mods[m].get("excludeKinds"), []) as Array).has(kind):
			pool.append(m)
	if pool.is_empty():
		# pick sur un tableau vide : le tirage est fait, arr[0] vaut undefined, `?? null` rend null.
		D6Rng.rand(game.rng.gen)
		return null
	return D6Js.nz(D6Rng.pick(game.rng.gen, pool), null)

## Comportement temporel des modificateurs, à chaque image où l'élite vit (même étourdi :
## l'étourdissement INTERROMPT une canalisation d'invocateur). Appelé par enemies.
static func update_elite_mod(game: Dictionary, e: Dictionary, dt: float) -> void:
	if D6Js.nz(e.get("leechFlash"), 0.0) > 0.0:
		e.leechFlash = maxf(0.0, e.leechFlash - dt)
	var m = game.tuning.elite.mods.get(e.eliteMod)
	if m == null:
		return
	if not e.has("modPhase"):
		e.modPhase = "idle"
		e.modT = D6Js.nz(m.get("firstDelay"), 0.0)
		e.modDur = 0.0
	if e.eliteMod == "bouclier":
		_shield_tick(e, m, dt)
	elif e.eliteMod == "invocateur":
		_summon_tick(game, e, m, dt)

## Bouclier : repos -> anneau d'annonce (warn) -> bulle d'immunité (duration) -> repos.
static func _shield_tick(e: Dictionary, m: Dictionary, dt: float) -> void:
	e.modT -= dt
	if e.modPhase == "up":
		e.invuln = maxf(0.0, e.modT)
	if e.modT > 0.0:
		return
	if e.modPhase == "idle":
		e.modPhase = "warn"
		e.modT = m.warn
		e.modDur = m.warn
	elif e.modPhase == "warn":
		e.modPhase = "up"
		e.modT = m.duration
		e.modDur = m.duration
		e.invuln = m.duration
	else:
		e.modPhase = "idle"
		e.modT = m.every
		e.modDur = 0.0
		e.invuln = 0.0

## Invocateur : repos -> canalisation (alerte inoffensive) -> cercles d'invocation -> repos.
static func _summon_tick(game: Dictionary, e: Dictionary, m: Dictionary, dt: float) -> void:
	if e.stun > 0.0:
		# Étourdi : la canalisation est perdue (contre-jeu), le cycle repart de zéro.
		if e.modPhase == "channel":
			e.modPhase = "idle"
			e.modT = m.every
			e.modDur = 0.0
		return
	e.modT -= dt
	if e.modT > 0.0:
		return
	if e.modPhase == "channel":
		D6AiCommon.summon_around(game, e, m.kind, minf(m.count, D6AiCommon.summon_room(game)), m.summonMinR, m.summonMaxR, m.summonMinPlayerDist)
		e.modPhase = "idle"
		e.modT = m.every
		e.modDur = 0.0
		return
	if D6AiCommon.summon_room(game) <= 0.0:
		e.modT = m.retry # plafond atteint : réessaie un peu plus tard
		return
	e.modPhase = "channel"
	e.modT = m.channel
	e.modDur = m.channel
	D6State.emit(game, "enemyAttack", {"id": e.id, "x": e.x, "y": e.y, "enemy": "summon"})

## Vampirique : `src` (l'ennemi qui a porté le coup) vient d'infliger `dealt` PV au héros.
## Sans effet pour un autre modificateur, un ennemi mort ou un coup esquivé (dealt = 0).
static func foe_dealt(game: Dictionary, src, dealt) -> void:
	if src == null or D6Js.truthy(src.get("dead")) or src.get("eliteMod") != "vampirique" or not (dealt > 0.0):
		return
	var m: Dictionary = game.tuning.elite.mods.vampirique
	src.leechFlash = m.flash
	src.hp = minf(src.maxHp, src.hp + D6Js.jround(dealt * m.leech))
