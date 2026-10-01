class_name D6KitSkills
extends RefCounted
## Portage de src/sim/kit_skills.mjs.
## COMPÉTENCES (bouton Lance) autres que la Lance infernale, jouées selon `kind` :
##   chain   — Chaîne d'Enfer : crochet qui harponne, étourdit et tire l'ennemi au contact
##   bond    — Bond du bourreau : saut invulnérable vers la cible, impact à l'atterrissage
##   brasier — Brasier d'âmes : pot lancé sur la cible, impact puis sol qui brûle
##   volee   — Volée d'épines : éventail de traits
##
## player garde la machine à états (état 'cast', recharge, tampon, annulations) et appelle :
##   begin_kit_skill   au début du lancer (mémorise la cible ; le Bond part aussitôt)
##   update_leap       à chaque pas du Bond (rend true à l'atterrissage)
##   release_kit_skill à la fin du lancer, ou AVANT un dash / Super qui l'interrompt : une
##                     recharge consommée produit toujours son effet (comme la Lance).

const LAND_OVERLAP := 0.5 # le Bond s'arrête quand le héros chevauche la cible de moitié
static var _point := {"x": 0.0, "y": 0.0}

## Début du lancer : `aim` = visée résolue par player (objet partagé : on le copie).
static func begin_kit_skill(game: Dictionary, s: Dictionary, aim: Dictionary) -> void:
	var p: Dictionary = game.player
	p.cast = {"kind": s.kind, "targetId": aim.targetId, "targetDist": aim.targetDist, "vx": 0.0, "vy": 0.0}
	if s.kind == "bond":
		_begin_leap(game, s)

static func _begin_leap(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var d: float = s.range
	var e = D6KitCommon.live_enemy(game, p.cast.targetId)
	if e != null:
		d = D6Geo.clampv(p.cast.targetDist - (p.r + e.r) * LAND_OVERLAP, s.minRange, s.range)
	var speed: float = d / s.leapTime
	p.cast.vx = p.castDirX * speed
	p.cast.vy = p.castDirY * speed
	p.castT = s.leapTime
	p.iframes = maxf(p.iframes, s.leapTime + s.iframesGrace)
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": D6Trig.atan2(p.castDirY, p.castDirX), "skill": "bond"})

## Un pas du Bond (état 'cast'). Rend true quand le héros a atterri.
static func update_leap(game: Dictionary, dt: float) -> bool:
	var p: Dictionary = game.player
	if p.castT <= 0.0 or p.get("cast") == null:
		_land(game)
		return true
	p.vx = p.cast.vx
	p.vy = p.cast.vy
	p.castT -= dt
	return false

static func _land(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning.skill
	p.cast = null
	p.vx = 0.0
	p.vy = 0.0
	D6KitCommon.hit_circle(game, p.x, p.y, s.radius, {"kind": "skill", "amount": s.damage, "knockback": s.knockback, "stun": D6Js.nz(s.get("stun"), 0.0), "hitstop": s.hitstop, "canCrit": true, "shake": D6Js.nz(s.get("shake"), 0.0)})
	D6State.emit(game, "explode", {"x": p.x, "y": p.y, "r": s.radius, "hero": true, "kind": "bond"})

## Effet de la compétence au relâcher (ou à l'interruption).
static func release_kit_skill(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning.skill
	var angle: float = D6Trig.atan2(p.castDirY, p.castDirX)
	match s.kind:
		"bond":
			# Interrompu en plein saut (dash, Super) : il atterrit là où il est.
			if p.get("cast") != null:
				_land(game)
			return
		"chain":
			D6KitShots.spawn_shot(game, {
				"kind": "hook", "x": p.x, "y": p.y, "vx": p.castDirX * s.speed, "vy": p.castDirY * s.speed, "r": s.radius, "range": s.range,
				"pierce": 0.0, "damage": s.damage, "source": "skill", "knockback": s.knockback, "hitstop": s.hitstop, "stun": D6Js.nz(s.get("stun"), 0.0),
				"pull": {"stopGap": s.pullGap, "mass": s.pullMass},
			})
		"volee":
			D6KitShots.fire_fan(game, angle, s.count, s.spread, {
				"kind": "thorn", "r": s.radius, "speed": s.speed, "range": s.range, "pierce": s.pierce, "damage": s.damage, "source": "skill",
				"knockback": s.knockback, "hitstop": s.hitstop,
			})
		"brasier":
			var cast = p.get("cast")
			var target_id = D6Js.nz(cast.get("targetId"), 0.0) if cast != null else 0.0
			var target: Dictionary = D6KitCommon.throw_point(game, p.castDirX, p.castDirY, target_id, s.range, s.throwDist, _point)
			D6KitZones.spawn_zone(game, {
				"kind": "pot", "x": p.x, "y": p.y, "x0": p.x, "y0": p.y, "tx": target.x, "ty": target.y, "flight": s.flight, "lift": 0.0,
				"r": s.radius, "damage": s.damage, "knockback": s.knockback, "hitstop": s.hitstop,
				"duration": s.duration, "tick": s.tick, "burnDps": s.burnDps, "burnRefresh": s.burnRefresh,
			})
		_:
			return
	# Recul léger au tir (sensation de puissance), comme la Lance.
	var recoil: float = D6Js.nz(s.get("recoil"), 0.0)
	p.vx -= p.castDirX * recoil
	p.vy -= p.castDirY * recoil
	p.cast = null
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": angle, "skill": s.kind})
