class_name D6KitSkills
extends RefCounted
## Portage de src/sim/kit_skills.mjs.
## COMPÉTENCES autres que la Lance infernale, jouées selon `kind`. La compétence en cours est
## celle de l'emplacement player.castSlot (D6Loadout.cast_def) :
##   chain   — Chaîne d'Enfer : crochet qui harponne, étourdit et tire l'ennemi au contact
##   bond    — Bond du bourreau : saut invulnérable vers la cible, impact à l'atterrissage. Il vole
##             au-dessus du terrain bas comme le SAUT (déplacement de classe du Bourreau, player) :
##             les deux partagent le vol (D6KitCommon.flight_moves) ; le Bond reste une attaque.
##   brasier — Brasier d'âmes : pot lancé sur la cible, impact puis sol qui brûle
##   volee   — Volée d'épines : éventail de traits
##   canal   — un ancien Super (Colère, Sentence, Nuée) joué comme compétence : channel_def donne ses
##             réglages, player le joue dans l'état 'super'
##   sceau, riposte, faille, hachette, proie, trait — les compétences NEUVES de l'étape 4 : leur
##             effet est dans sim/kit_neuves.gd (une famille par classe), lancé d'ici comme les autres
##   ombre, grace, grele — la quatrième de chaque classe (étape 5), mêmes fichiers, même chemin
## Les AMÉLIORATIONS EXCLUSIVES de l'arbre (sim/tree.gd) ajoutent des nombres à la compétence :
## `rebound` (Bond), `noPull` / `pierce` / `vuln` (Chaîne), `chill` / `stun` (Brasier)… lus ici.
##
## player garde la machine à états (état 'cast', recharge, tampon, annulations) et appelle :
##   begin_kit_skill   au début du lancer (mémorise la cible ; le Bond part aussitôt)
##   update_leap       à chaque pas du Bond (rend true à l'atterrissage)
##   release_kit_skill à la fin du lancer, ou AVANT un dash / Super qui l'interrompt : une
##                     recharge consommée produit toujours son effet (comme la Lance).

const CHANNEL_OWN := ["name", "kind", "icon", "text", "super", "cooldown", "castTime", "aimed"] # champs d'une compétence `canal` qui ne règlent pas le Super joué
const LAND_OVERLAP := 0.5 # le Bond s'arrête quand le héros chevauche la cible de moitié
const Neuves := preload("res://sim/kit_neuves.gd")
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
	_plan_leap(game, s)
	p.iframes = maxf(p.iframes, s.leapTime + s.iframesGrace)
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": D6Trig.atan2(p.castDirY, p.castDirX), "skill": "bond", "slot": p.castSlot})

## Le Bond FRANCHIT le terrain bas comme le déplacement de classe (même vol : D6KitCommon.flight_moves)
## et se pose sur la terre ferme : si l'arrivée tombait dans une rivière, il est raccourci.
static func _plan_leap(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var moves := 0
	var left: float = s.leapTime
	while left > 0.0: # les pas de update_leap : un déplacement tant que castT > 0
		moves += 1
		left -= D6Data.DT
	var firm := D6KitCommon.flight_moves(game, p.cast.vx, p.cast.vy, moves)
	if firm < moves:
		p.castT = maxf(0.0, (float(firm) - 0.5) * D6Data.DT)
		D6KitCommon.flight_cut(game, p.cast.vx, p.cast.vy, moves, firm, "bond")

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
	var s: Dictionary = D6Loadout.cast_def(game)
	p.cast = null
	p.vx = 0.0
	p.vy = 0.0
	D6KitCommon.hit_circle(game, p.x, p.y, s.radius, {"kind": "skill", "amount": s.damage, "knockback": s.knockback, "stun": D6Js.nz(s.get("stun"), 0.0), "hitstop": s.hitstop, "canCrit": true, "shake": D6Js.nz(s.get("shake"), 0.0)})
	D6State.emit(game, "explode", {"x": p.x, "y": p.y, "r": s.radius, "hero": true, "kind": "bond"})
	_rebound(game, s)

## « Double saut » (amélioration du Bond) : après un Bond, le suivant est prêt en `rebound` s — une
## fois ; le Bond d'après retrouve sa recharge entière.
static func _rebound(game: Dictionary, s: Dictionary) -> void:
	if s.get("rebound") == null:
		return
	var st: Dictionary = game.player.slots[int(game.player.castSlot)]
	var chained: bool = D6Js.truthy(st.get("rebound"))
	st.rebound = not chained
	if not chained:
		st.cd = minf(st.cd, s.rebound)

## Réglages joués par une compétence `canal` : ceux de l'ancien Super qu'elle nomme (tuning.supers),
## recouverts par les nombres de la compétence (ses rangs, son amélioration exclusive).
static func channel_def(game: Dictionary, s: Dictionary) -> Dictionary:
	var def: Dictionary = D6Js.clone(game.tuning.supers[s["super"]])
	for key in s:
		if not CHANNEL_OWN.has(key):
			def[key] = s[key]
	return def

## Effet de la compétence au relâcher (ou à l'interruption).
static func release_kit_skill(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = D6Loadout.cast_def(game)
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
				"pierce": D6Js.nz(s.get("pierce"), 0.0), "damage": s.damage, "source": "skill", "knockback": s.knockback, "hitstop": s.hitstop, "stun": D6Js.nz(s.get("stun"), 0.0),
				"pull": null if D6Js.truthy(s.get("noPull")) else {"stopGap": s.pullGap, "mass": s.pullMass},
				"vuln": D6Js.nz(s.get("vuln"), 0.0), "vulnMult": D6Js.nz(s.get("vulnMult"), 0.0),
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
				"r": s.radius, "damage": s.damage, "knockback": s.knockback, "hitstop": s.hitstop, "stun": D6Js.nz(s.get("stun"), 0.0),
				"chill": D6Js.nz(s.get("chill"), 0.0), "chillMult": D6Js.nz(s.get("chillMult"), 1.0),
				"duration": s.duration, "tick": s.tick, "burnDps": s.burnDps, "burnRefresh": s.burnRefresh,
			})
		"ruee", "hurlement", "embrasement":
			# Actions de la Forme du Damné (elles tiennent les trois emplacements pendant la forme).
			D6KitSupers.form_action(game, s)
		"sceau", "riposte", "faille", "hachette", "proie", "trait", "ombre", "grace", "grele":
			angle = Neuves.release(game, s, angle) # compétences neuves (étapes 4 et 5)
		_:
			return
	# Recul léger au tir (sensation de puissance), comme la Lance.
	var recoil: float = D6Js.nz(s.get("recoil"), 0.0)
	p.vx -= p.castDirX * recoil
	p.vy -= p.castDirY * recoil
	p.cast = null
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": angle, "skill": s.kind, "slot": p.castSlot})
