extends RefCounted
## ULTIME « TRANSFORMATION » — Forme du Damné (Revenant). Chargé par D6KitSupers (pas de class_name).
## Données : tuning.supers.forme_damne (data/classes.json).
##
## L'état de la forme vit dans player.ult = {kind: 'forme', t, max, slots, states} (null hors forme) :
##   t, max  — secondes restantes et durée totale (`formTime` + bonus de durée du Super) ;
##   slots   — les trois identifiants équipés AVANT la forme ;
##   states  — leurs états (recharge, charges) AVANT la forme, rendus tels quels à la fin : pendant
##             la forme, le kit d'origine est FIGÉ (ses recharges ne courent pas, il ne gagne ni ne
##             perd de charge).
## Pendant la forme :
##   - la jauge d'ultime est la minuterie (player.superCharge = t / max) et ne se remplit pas ;
##   - l'arme est remplacée par les GRIFFES (`weapon` : combo et frappe de dash), quelle que soit
##     l'arme équipée : D6Loadout.resolve_kit branche tuning.combo / dashStrike / weapon dessus ;
##     leurs coups volent `lifesteal` de vie en plus du vol de vie du build ;
##   - les trois emplacements portent les actions de forme (`slots`, `actions`) : game.kit.slots et
##     D6Loadout.slot_def / slot_view les rendent, l'affichage n'a rien à savoir. Elles passent par
##     le lancer ordinaire d'une compétence (état 'cast', recharge propre) :
##       ruee        — Ruée spectrale : le héros traverse `range` u d'un trait (il se pose sur la
##                     terre ferme, un mur l'arrête) et blesse tout ce qui est sur le passage ;
##       hurlement   — étourdit tout autour ;
##       embrasement — met fin à la forme : explosion de `damage` (forme presque finie) à
##                     `damageMax` (forme à peine commencée), selon le temps qui restait ;
##   - le déplacement de classe reste le dash.
## La forme finit quand la minuterie est vide (après le lancer en cours, s'il y en a un), à
## l'embrasement, à la mort, au changement de salle. Dégâts des actions : source 'super'.

const RUSH_STEP := 10.0 # u : pas du vol de la Ruée (D6Physics.fly_plan)

## Entre dans la forme (début du geste de lancement).
static func begin(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var life: float = s.formTime + D6Js.nz(p.stats.get("superDurationBonus"), 0.0)
	p.ult = {"kind": "forme", "t": life, "max": life, "slots": game.kit.slots.duplicate(), "states": D6Js.clone(p.slots)}
	for st in p.slots:
		st.cd = 0.0
		st.charges = 0.0
	if p.buffer.action == "skill":
		p.buffer.action = null # une compétence d'avant la forme ne part pas en action de forme
	D6Loadout.resolve_kit(game)
	D6State.emit(game, "formStart", {"x": p.x, "y": p.y, "time": life})

## Un pas de la forme : la minuterie descend, la jauge la suit.
static func tick(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var u = p.get("ult")
	if u == null:
		return
	if p.state == "dead":
		end(game, "mort")
		return
	u.t = maxf(0.0, u.t - dt)
	p.superCharge = u.t / u.max
	if u.t <= 0.0 and p.state != "cast" and p.state != "super":
		end(game, "temps")

## Sort de la forme : arme et emplacements d'avant, avec leurs recharges et leurs charges d'avant.
static func end(game: Dictionary, reason: String) -> void:
	var p: Dictionary = game.player
	var u = p.get("ult")
	if u == null:
		return
	p.ult = null
	p.slots = u.states
	p.superCharge = 0.0
	if p.buffer.action == "skill":
		p.buffer.action = null
	if p.state == "cast":
		p.state = "free"
		p.stateTime = 0.0
	p.cast = null
	D6Loadout.resolve_kit(game)
	D6State.emit(game, "formEnd", {"x": p.x, "y": p.y, "reason": reason})

## Effet d'une action de forme, à la fin de son lancer (D6KitSkills.release_kit_skill).
static func action(game: Dictionary, s: Dictionary) -> void:
	match s.kind:
		"ruee":
			_rush(game, s)
		"hurlement":
			_howl(game, s)
		"embrasement":
			_burst(game, s)

static func _rush(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var x0: float = p.x
	var y0: float = p.y
	D6Physics.fly_plan(game.room, p, p.castDirX * RUSH_STEP, p.castDirY * RUSH_STEP, int(ceilf(s.range / RUSH_STEP)))
	p.x = D6Physics.fly_end.x
	p.y = D6Physics.fly_end.y
	p.vx = 0.0
	p.vy = 0.0
	p.iframes = maxf(p.iframes, D6Js.nz(s.get("iframes"), 0.0))
	var half: float = s.width / 2.0
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var reach: float = half + e.r
		if D6Geo.point_seg_dist2(e.x, e.y, x0, y0, p.x, p.y) >= reach * reach:
			continue
		D6Combat.damage_enemy(game, e, {
			"kind": "super", "amount": s.damage, "dirX": p.castDirX, "dirY": p.castDirY, "knockback": s.knockback,
			"hitstop": s.hitstop, "canCrit": true, "shake": D6Js.nz(s.get("shake"), 0.0),
		})
	D6State.emit(game, "formRush", {"x0": x0, "y0": y0, "x": p.x, "y": p.y, "width": s.width})

static func _howl(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	D6KitCommon.hit_circle(game, p.x, p.y, s.radius, {
		"kind": "super", "amount": s.damage, "knockback": s.knockback, "stun": D6Js.nz(s.get("stun"), 0.0),
		"hitstop": s.hitstop, "canCrit": false, "shake": D6Js.nz(s.get("shake"), 0.0),
	})
	D6State.emit(game, "formHowl", {"x": p.x, "y": p.y, "r": s.radius})

## Dégâts de l'embrasement s'il partait maintenant : de `damage` à `damageMax` selon le temps restant.
static func burst_damage(game: Dictionary, s: Dictionary) -> float:
	var u = game.player.get("ult")
	var frac: float = u.t / u.max if u != null else 0.0
	return D6Geo.lerpv(s.damage, D6Js.nz(s.get("damageMax"), s.damage), frac)

static func _burst(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var u = p.get("ult")
	var amount := burst_damage(game, s)
	D6KitCommon.hit_circle(game, p.x, p.y, s.radius, {
		"kind": "super", "amount": amount, "knockback": s.knockback, "stun": D6Js.nz(s.get("stun"), 0.0),
		"hitstop": s.hitstop, "canCrit": false, "shake": D6Js.nz(s.get("shake"), 0.0),
	})
	D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, s.radius)
	D6State.emit(game, "formBurst", {"x": p.x, "y": p.y, "r": s.radius, "frac": u.t / u.max if u != null else 0.0, "amount": amount})
	end(game, "embrasement")
