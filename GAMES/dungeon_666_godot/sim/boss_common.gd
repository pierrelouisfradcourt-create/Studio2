class_name D6BossCommon
extends RefCounted
## Portage de src/sim/boss_common.mjs.
## Briques communes à tous les Gardiens (module feuille, sans dépendance vers boss.gd) : états,
## visée, repos. Chaque modèle de Gardien vit dans son fichier sim/boss_<modèle>.gd.

const ROOM_POINT_STEPS := 16.0 # pas de recherche vers le centre (résolution, pas un réglage de jeu)

static func boss_def(game: Dictionary, e: Dictionary) -> Dictionary:
	return game.tuning.boss[e.kind]

## Les télégraphes d'un Gardien ne raccourcissent JAMAIS (équité, spec §4.1).
static func wmult() -> float:
	return 1.0

static func to_player(game: Dictionary, e: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var d := maxf(1e-6, sqrt(dx * dx + dy * dy))
	return {"dx": dx / d, "dy": dy / d, "d": d}

static func set_state(e: Dictionary, s) -> void:
	_end_exposure(e)
	e.state = s
	e.stateTime = 0.0
	e.patternStep = 0.0
	e.patternT = 0.0
	# Sous-étape d'un pattern (modèles ajoutés) : remise à zéro à chaque changement d'état, y
	# compris quand une transition de phase interrompt un pattern.
	e.sub = null
	e.subT = 0.0

## Fin de pattern : l'alerte disparaît, le Gardien souffle (fenêtre de punition).
static func to_rest(_game: Dictionary, e: Dictionary) -> void:
	e.tele = null
	set_state(e, "rest")

# ---------------------------------------------------------------- briques des modèles ajoutés

## Passe à la sous-étape `name` d'un pattern (chronomètre e.subT remis à zéro).
static func set_sub(e: Dictionary, name) -> void:
	e.sub = name
	e.subT = 0.0

## Le Gardien reste sur place ce pas-ci (il arme, frappe ou récupère).
static func hold_still(e: Dictionary) -> void:
	e.vx = 0.0
	e.vy = 0.0

## Zone de danger d'un Gardien : dégâts mis à l'échelle de l'étage, et rattachée au Gardien
## (sourceId) — s'il meurt pendant le télégraphe, l'attaque est annulée.
static func boss_hazard(game: Dictionary, e: Dictionary, h: Dictionary):
	var hz := {"sourceId": e.id, "hitsPlayer": true, "hitsEnemies": false}
	hz.merge(h, true)
	hz.damage = h.damage * e.dmgScale
	return D6Combat.spawn_hazard(game, hz)

## Point faible exposé : dégâts reçus majorés de `mult` pendant `duration` s. Statut PROPRE
## (e.exposed / e.exposedMult : appliqué par combat.damage_enemy, décompté par le moteur, éteint
## dès que le pattern s'achève — set_state), distinct de la vulnérabilité générique des
## bénédictions et gadgets (e.vuln / e.vulnMult, ex. Charme fatal). Les deux majorations se
## cumulent sans que l'une prolonge l'autre, et seul e.exposed fait dessiner le point faible.
static func expose(e: Dictionary, duration: float, mult: float) -> void:
	e.exposed = maxf(_num(e.get("exposed")), duration)
	e.exposedMult = maxf(_num(e.get("exposedMult")), mult)
	hold_vuln_flag(e)

## Le statut générique « vulnérable » (e.vuln > 0) reste vrai pendant toute l'exposition, mais
## SANS majoration propre : s'il était retombé, on le relève avec vulnMult = 0 ; une
## vulnérabilité de bénédiction en cours n'est ni prolongée ni modifiée.
static func hold_vuln_flag(e: Dictionary) -> void:
	if not (_num(e.get("exposed")) > 0.0) or _num(e.get("vuln")) > 0.0:
		return
	e.vuln = e.exposed
	e.vulnMult = 0.0

## Fin d'exposition (pattern terminé ou interrompu) : rien ne survit à la fenêtre de punition.
static func _end_exposure(e: Dictionary) -> void:
	if not (_num(e.get("exposed")) > 0.0) and not D6Js.truthy(e.get("exposedMult")):
		return
	e.exposed = 0.0
	e.exposedMult = 0.0
	if not (_num(e.get("vulnMult")) > 0.0):
		e.vuln = 0.0 # drapeau levé par l'exposition seule

## Récupération immobile et exposée qui clôt un pattern (la fenêtre de punition), puis repos.
## À appeler à chaque pas tant que la sous-étape est 'recover'.
static func exposed_recovery(game: Dictionary, e: Dictionary, duration: float, mult: float, dt: float) -> void:
	hold_still(e)
	if e.get("sub") != "recover":
		set_sub(e, "recover")
		expose(e, duration, mult)
	e.subT += dt
	if e.subT >= duration:
		to_rest(game, e)

## Point jouable le plus proche de (x, y) pour un corps de rayon r (murs ; obstacles évités).
static func room_point(game: Dictionary, x: float, y: float, r: float) -> Dictionary:
	var room: Dictionary = game.room
	var px := D6Geo.clampv(x, room.pad + r, room.w - room.pad - r)
	var py := D6Geo.clampv(y, room.pad + r, room.h - room.pad - r)
	if not D6Js.truthy(D6Physics.point_blocked(room, px, py, r)):
		return {"x": px, "y": py}
	# Sur un obstacle : on recule vers le centre de la salle jusqu'à trouver de la place.
	var cx: float = room.w / 2.0
	var cy: float = room.h / 2.0
	var k := 1.0
	while k <= ROOM_POINT_STEPS:
		var f := k / ROOM_POINT_STEPS
		var qx := px + (cx - px) * f
		var qy := py + (cy - py) * f
		if not D6Js.truthy(D6Physics.point_blocked(room, qx, qy, r)):
			return {"x": qx, "y": qy}
		k += 1.0
	return {"x": cx, "y": cy}

## Serviteurs invoqués encore en jeu (vivants ou en cours d'apparition).
static func summoned_alive(game: Dictionary) -> float:
	var n := 0.0
	for o in game.enemies:
		if not D6Js.truthy(o.get("dead")) and D6Js.truthy(o.get("summoned")):
			n += 1.0
	for s in game.spawns:
		if D6Js.truthy(s.get("summoned")):
			n += 1.0
	return n

## Nombre lu dans un champ qui peut manquer (`e.exposed ?? 0`). Ce module ne s'en sert que là où
## JavaScript donne le même résultat pour `undefined` et pour 0 : comparaisons « > 0 » et
## `Math.max(x ?? 0, …)`.
static func _num(v) -> float:
	return 0.0 if v == null else float(v)
