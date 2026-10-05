class_name D6KitSupers
extends RefCounted
## Portage de src/sim/kit_supers.mjs, étendu par le combat V3 (étape 2 : les trois ULTIMES).
##
## ULTIMES DE CLASSE, un TYPE par classe (design/COMBAT_V3.md), joués selon `kind` :
##   forme — Forme du Damné (Revenant)      : transformation limitée (sim/ult_forme.gd)
##   magie — Sentence capitale (Bourreau)   : un seul geste qui frappe toute la salle (sim/ult_magie.gd)
##   meute — Meute des Limbes (Chasseresse) : trois limiers alliés (sim/ult_meute.gd)
## Les trois se lancent comme tout Super (jauge pleine, attaque maintenue : player) et commencent
## par un geste dans l'état 'super' (invulnérable, `duration` s). La forme et la meute AGISSENT
## ensuite pendant des secondes : tant qu'un ultime agit (acting), il ne se relance pas, la jauge
## ne se remplit pas — elle sert de minuterie et se vide. Ce module est la façade : le reste de la
## simulation n'appelle que lui.
##
## ANCIENS SUPERS (gardés pour l'arbre de compétences, `reserve` dans les données : ils ne sont
## plus l'ultime d'aucune classe) : la Colère est jouée par player, et ici
##   sentence — Sentence : exécutions auto-visées à des instants fixes du Super
##   nuee     — Nuée de traits : un trait toutes les `interval` s sur les ennemis les plus proches
## player garde l'état 'super' (le héros y est invulnérable : combat), la durée, la locomotion et
## la fin ; ce module ne fait que le « tic » propre au Super. Les dégâts portent la source 'super'
## (ils ne rechargent pas la jauge ; « Gloire charnelle » s'y applique).

const Forme := preload("res://sim/ult_forme.gd")
const Magie := preload("res://sim/ult_magie.gd")
const Meute := preload("res://sim/ult_meute.gd")

## Sorte d'ultime dite à l'affichage (D6Player.ultimate_view) pour chaque `kind` de Super.
const VIEW_KINDS := {"forme": "forme", "magie": "magie", "meute": "invocation"}
const VIEW_OTHER := "attaque" # un ancien Super (Colère, Sentence, Nuée)

static func start_kit_super(game: Dictionary) -> void:
	var s: Dictionary = game.tuning["super"]
	reset_clock(game)
	match s.kind:
		"forme":
			Forme.begin(game, s)
		"meute":
			Meute.summon(game, s)

## Horloge d'un Super qui commence (ultime, ou compétence `canal` : player).
static func reset_clock(game: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superClock = 0.0
	p.superStep = 0.0
	p.superShotT = 0.0
	p.superRot = 0.0

static func tick_kit_super(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superClock += dt
	match s.kind:
		"sentence":
			_sentence(game, s)
		"nuee":
			_nuee(game, dt, s)
		"magie":
			Magie.tick(game, s)

# ---------------------------------------------------------------- ultimes qui durent

## La forme en cours du héros (player.ult), ou null. Sûr avant la naissance du héros.
static func form_of(game: Dictionary):
	var p = game.get("player")
	if not (p is Dictionary):
		return null
	var u = p.get("ult")
	return u if u is Dictionary and u.get("kind") == "forme" else null

## Vrai tant qu'un ultime AGIT : geste en cours (état 'super'), forme active, limier vivant. Il ne
## se relance pas, et rien ne remplit la jauge (coups, esquive parfaite, procs).
static func acting(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	return p.state == "super" or p.get("ult") != null or not game.allies.is_empty()

## Un pas des ultimes qui durent (chaque pas de simulation, après le héros) : minuterie de la
## forme, vie et combat des limiers ; à la mort du héros, tout s'arrête.
static func tick(game: Dictionary, dt: float) -> void:
	Forme.tick(game, dt)
	Meute.tick(game, dt)

## Remet tout en ordre (changement de salle, reprise après la mort) : forme terminée, kit d'origine
## rendu, limiers retirés.
static func reset(game: Dictionary, reason: String) -> void:
	Forme.end(game, reason)
	Meute.dismiss(game, reason)

## Effet d'une action de forme à la fin de son lancer (appelé par D6KitSkills).
static func form_action(game: Dictionary, s: Dictionary) -> void:
	Forme.action(game, s)

## Vol de vie en plus des coups d'arme pendant la forme (0 hors forme, ou pour une autre source).
static func form_lifesteal(game: Dictionary, kind) -> float:
	if form_of(game) == null or (kind != "melee" and kind != "strike"):
		return 0.0
	return D6Js.nz(game.tuning["super"].get("lifesteal"), 0.0)

## Un ennemi est-il accaparé par un limier ce pas-ci ? (appelé par D6Enemies ; voir ult_meute)
static func distract(game: Dictionary, e: Dictionary, def: Dictionary) -> bool:
	return not game.allies.is_empty() and Meute.distract(game, e, def)

## Un tir ennemi s'arrête-t-il sur un limier ? (appelé par D6Projectiles)
static func block_shot(game: Dictionary, pr: Dictionary, ox: float, oy: float) -> bool:
	return not game.allies.is_empty() and Meute.block_shot(game, pr, ox, oy)

## Blesse un limier (zone de danger : D6Projectiles).
static func hurt_ally(game: Dictionary, h: Dictionary, amount: float, source) -> bool:
	return Meute.hurt(game, h, amount, source)

## Ce que l'affichage lit de l'ULTIME, sans connaître l'intérieur (D6Player.ultimate_view) :
##   id, name, icon, text : l'ultime de la classe (data/classes.json, `supers`)
##   kind      : "forme" | "magie" | "invocation" ("attaque" pour un ancien Super)
##   charge    : jauge, 0..1 ; ready : pleine et lançable (aucun ultime n'agit)
##   holdFrac  : part du maintien déjà tenue, 0..1 (1 = il part)
##   active    : l'ultime agit (geste, forme, limier vivant)
##   timeFrac  : part de sa durée qui RESTE, 0..1 (0 hors ultime) ; timeLeft : en secondes
##   allies    : limiers vivants
static func view(game: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning["super"]
	var u = form_of(game)
	var left := 0.0
	var frac := 0.0
	if u != null:
		left = u.t
		frac = u.t / u.max
	for h in game.allies:
		if not h.dead and h.life > left:
			left = h.life
			frac = h.life / h.lifeMax
	if left <= 0.0 and p.state == "super" and p.get("channel") == null: # pas une compétence `canal`
		left = maxf(0.0, p.superT)
		frac = D6Geo.clampv(p.superT / maxf(1e-6, s.duration), 0.0, 1.0)
	var kit = game.get("kit")
	return {
		"id": kit.get("superId") if kit is Dictionary else null, "kind": VIEW_KINDS.get(s.kind, VIEW_OTHER),
		"name": s.name, "icon": D6Js.nz(s.get("icon"), "super"), "text": D6Js.nz(s.get("text"), ""),
		"charge": p.superCharge, "ready": p.superCharge >= 1.0 and not acting(game),
		"holdFrac": D6Geo.clampv(p.superHold / s.holdTime, 0.0, 1.0),
		"active": acting(game), "timeFrac": frac, "timeLeft": left, "allies": float(game.allies.size()),
	}

# ---------------------------------------------------------------- anciens Supers (réserve)

static func _sentence(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var strikes: Array = s.strikes
	while p.superStep < float(strikes.size()) and p.superClock >= strikes[int(p.superStep)].at:
		var st: Dictionary = strikes[int(p.superStep)]
		p.superStep += 1.0
		var aim: Dictionary = D6Aim.compute_aim(game, p.manualAimX, p.manualAimY, s.get("aimRange"))
		var angle: float = D6Trig.atan2(aim.y, aim.x)
		p.facing = angle
		var hits := D6KitCommon.hit_sector(game, p.x, p.y, st.range, angle, st.arc * D6Data.DEG, {
			"kind": "super", "amount": st.damage * D6Js.nz(s.get("damageMult"), 1.0), "knockback": st.knockback, "stun": D6Js.nz(st.get("stun"), 0.0), "hitstop": st.hitstop, "canCrit": true, "shake": D6Js.nz(st.get("shake"), 0.0),
		})
		if hits > 0.0 and s.get("healPerHit") != null:
			D6Combat.heal_player(game, hits * s.healPerHit, true) # « Dîme de sang » (amélioration de l'arbre)
		D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": st.range, "super": "sentence", "angle": angle, "arc": st.arc * D6Data.DEG, "step": p.superStep})

## Les `n` ennemis visibles les plus proches à portée, du plus proche au plus lointain.
static func _nearest_targets(game: Dictionary, reach_max: float, n: float) -> Array:
	var p: Dictionary = game.player
	var list: Array = []
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		var d2: float = D6Geo.dist2(p.x, p.y, e.x, e.y)
		var reach: float = reach_max + e.r
		if d2 > reach * reach:
			continue
		if not D6Physics.line_of_sight(game.room, p.x, p.y, e.x, e.y):
			continue
		list.append({"e": e, "d2": d2})
	# Tri par distance puis par id : ordre TOTAL (ids uniques), la stabilité du tri ne joue pas.
	list.sort_custom(func(a, b): return a.d2 < b.d2 or (a.d2 == b.d2 and a.e.id < b.e.id))
	return list.slice(0, maxi(0, int(n)))

static func _nuee(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superShotT -= dt
	if p.superShotT > 0.0:
		return
	p.superShotT += s.interval
	var targets: Array = _nearest_targets(game, s.range, s.targets)
	if targets.size() == 0:
		return
	var e: Dictionary = targets[int(fmod(p.superRot, float(targets.size())))].e
	p.superRot += 1.0
	var dx: float = e.x - p.x
	var dy: float = e.y - p.y
	var l: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
	D6KitShots.spawn_shot(game, {
		"kind": "star", "x": p.x, "y": p.y, "vx": (dx / l) * s.speed, "vy": (dy / l) * s.speed, "r": s.shotRadius, "range": s.range,
		"pierce": s.pierce, "damage": s.damage, "source": "super", "knockback": s.knockback, "hitstop": s.hitstop, "heavy": false,
	})
	D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": s.shotRadius, "super": "nuee", "angle": D6Trig.atan2(dy, dx)})
