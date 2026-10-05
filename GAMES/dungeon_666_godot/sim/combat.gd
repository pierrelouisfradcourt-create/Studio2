class_name D6Combat
extends RefCounted
## Portage de src/sim/combat.mjs.
## Résolution des dégâts — UN SEUL chemin pour toucher un ennemi (damage_enemy) et UN SEUL
## pour toucher le héros (damage_player). Les bénédictions n'exécutent pas de code : elles
## déclarent des « procs » (données) que ce module interprète. Pas d'import circulaire.
##
## VOCABULAIRE DES PROCS (bénédictions de boons, pouvoirs légendaires de loot) :
##   on     — quand : 'hit' (un coup du héros porte ; `sources` = sortes de coups concernées),
##            'kill' (un ennemi meurt), 'dash' (une charge de dash est dépensée), 'dodge' (esquive
##            parfaite), 'wallSlam' (un ennemi est projeté contre un mur), 'super' (le Super est
##            lancé), 'roomClear' (la salle est nettoyée), 'overheal' (un soin dépasse les PV max),
##            'passive' (lu à chaque calcul de dégâts).
##   when   — condition facultative, lue dans le contexte du déclencheur : 'finisher' (dernier coup
##            du combo), 'untouched' (salle nettoyée sans blessure).
##   chance — probabilité (flux rng.combat ; 1 = aucun tirage).
##   effect — sur la CIBLE : burn | chill | vuln | chain | stun | blast | cull | gold ;
##            sur le HÉROS : heal | surge | superCharge | dashCharge | gadgetCharge | gold (sans cible) ;
##            AUTOUR du héros : nova (dégâts, gel facultatif) | around (`apply` = effet de cible) ;
##            passifs : execute | fullHpBonus | goldPower | streakBonus | stunnedCrit | stunnedBonus
##            (dégâts en plus contre une cible étourdie : passif de l'arbre de compétences).
## Aucun effet ne connaît l'identifiant de la bénédiction qui le déclare.

# Sources de dégâts du héros qui déclenchent les procs « au toucher ».
const Arbre = preload("res://sim/tree.gd")
const PROC_SOURCES := ["melee", "strike", "skill", "gadget", "super"]
# Sources qui ne remplissent pas la jauge de Super (sinon le Super se recharge lui-même).
const NO_SUPER_CHARGE := ["super", "burn", "blast", "chain", "ally"] # "ally" : morsure d'un limier
const HIT_FLASH := 0.1 # s : éclat d'un ennemi touché
const HURT_FLASH := 0.35 # s : éclat du héros touché

## Champ numérique optionnel : absent ou null → 0 (en JavaScript, `undefined > 0` est faux).
static func _num(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return 0.0 if v == null else float(v)

## Opérande optionnel d'un calcul : absent → NaN, comme `undefined * x` en JavaScript.
static func _or_nan(v) -> float:
	return NAN if v == null else float(v)

## `ids.includes(id)` : comparaison par `==` (Array.has distingue 1 de 1.0, JavaScript non).
static func _has_id(ids: Array, id) -> bool:
	for v in ids:
		if v == id:
			return true
	return false

## Gel d'impact des coups du héros, puisé dans une réserve qui se recharge (anti-diaporama).
## D8 (lab.mjs) : en mode GLOBAL toute la scène se fige (game.hitstop) ; en mode LOCAL seuls le
## héros et la cible touchée se figent (player.freeze, e.freeze), le reste du monde continue.
static func apply_hitstop(game: Dictionary, h: float, target = null) -> void:
	var allowed := minf(h, game.hitstopBank)
	if game.tuning.hitstopMode == "local":
		var p: Dictionary = game.player
		if target != null and allowed > _num(target, "freeze"):
			target.freeze = allowed
		if allowed <= p.freeze:
			return
		game.hitstopBank -= allowed - p.freeze
		p.freeze = allowed
		return
	if allowed <= game.hitstop:
		return
	game.hitstopBank -= allowed - game.hitstop
	game.hitstop = allowed

## Gel imposé (héros touché, mort d'un élite, d'un boss) : hors réserve, toujours ressenti.
static func force_hitstop(game: Dictionary, h: float) -> void:
	if game.tuning.hitstopMode == "local":
		game.player.freeze = maxf(game.player.freeze, h)
		return
	game.hitstop = maxf(game.hitstop, h)

static func is_player_source(kind) -> bool:
	return kind != "enemyBlast" and kind != "wall"

## Dégâts avant critique : arme, compétence, procs d'exécution, Super, puis états de la cible.
## (Première partie de damageEnemy ; aucun tirage.)
static func _scaled_amount(game: Dictionary, e: Dictionary, src: Dictionary) -> float:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var st: Dictionary = p.stats
	var kind = src.get("kind")
	var amount: float = src.amount
	if is_player_source(kind) and kind != "wall":
		amount *= st.damageMult * (st.weaponDamage / t.weaponBase)
		if kind == "skill":
			amount *= st.skillDamageMult
		# Bonus d'exécution (bénédiction) contre les ennemis affaiblis.
		for pr in p.procs:
			var effect = pr.get("effect")
			if effect == "execute" and e.hp / e.maxHp <= pr.threshold and (not D6Js.truthy(pr.get("needsBurnChill")) or (e.burn > 0.0 and e.chill > 0.0)):
				amount *= 1.0 + pr.value
			if effect == "fullHpBonus" and p.hp >= p.maxHp:
				amount *= 1.0 + pr.value
			# Bourse pleine : par tranche de `per` or portée, `cap` tranches au plus.
			if effect == "goldPower":
				amount *= 1.0 + pr.value * minf(pr.cap, floorf(game.run.gold / pr.per))
			# Salles nettoyées d'affilée sans blessure (run.streak, remis à zéro par un coup reçu).
			if effect == "stunnedBonus" and e.stun > 0.0:
				amount *= 1.0 + pr.value
			if effect == "streakBonus":
				amount *= 1.0 + pr.value * minf(pr.cap, D6Js.nz(game.run.get("streak"), 0.0))
		# Élan passager du héros (effet « surge ») : dégâts en plus tant qu'il dure.
		if _num(p, "surge") > 0.0:
			amount *= 1.0 + p.surgeMult
		if kind == "super" or kind == "ally": # l'ultime et ce qu'il invoque
			amount *= D6Js.nz(st.get("superDamageMult"), 1.0)
	if e.get("eliteMod") == "blinde":
		amount *= t.elite.mods.blinde.damageTakenMult
	amount *= D6FoeDefense.ward_mult(game, e) # sous l'aura d'un Porte-étendard debout (foe_defense)
	if e.stun > 0.0:
		amount *= t.combat.stunDamageTakenMult
	if e.vuln > 0.0:
		amount *= 1.0 + e.vulnMult
	if _num(e, "exposed") > 0.0:
		amount *= 1.0 + _or_nan(e.get("exposedMult")) # point faible d'un Gardien (boss_common.expose)
	return amount

## Chances de critique en plus contre une cible sonnée (proc passif « stunnedCrit »), lues AVANT
## que ce coup ne sonne lui-même. (Dans damageEnemy : critBonus, même boucle que les dégâts.)
static func _crit_bonus(game: Dictionary, e: Dictionary, src: Dictionary) -> float:
	var kind = src.get("kind")
	var bonus := 0.0
	if is_player_source(kind) and kind != "wall":
		for pr in game.player.procs:
			if pr.get("effect") == "stunnedCrit" and e.stun > 0.0:
				bonus += pr.value
	return bonus

## Knockback, étourdissement, gel d'impact : les effets physiques d'un coup qui a porté.
static func _apply_impact(game: Dictionary, e: Dictionary, src: Dictionary) -> void:
	var t: Dictionary = game.tuning
	var st: Dictionary = game.player.stats
	var kind = src.get("kind")
	var is_boss := D6Js.truthy(e.get("boss"))
	# Knockback : on remplace l'élan courant s'il est plus faible (pas d'accumulation infinie).
	var knockback = src.get("knockback")
	if D6Js.truthy(knockback):
		var kb: float = (knockback * st.knockbackMult) / e.mass
		if e.get("eliteMod") == "blinde":
			kb *= t.elite.mods.blinde.knockbackMult
		if is_boss:
			kb *= t.guardians.knockbackMult
		var cur2: float = e.kvx * e.kvx + e.kvy * e.kvy
		if kb * kb > cur2:
			e.kvx = _or_nan(src.get("dirX")) * kb
			e.kvy = _or_nan(src.get("dirY")) * kb
	# En garde (il sort d'un étourdissement) : un coup d'arme blesse et repousse, sans ré-étourdir.
	var guarded: bool = _num(e, "guard") > 0.0 and t.combat.stunGuardSources.has(kind)
	var stun = src.get("stun")
	if D6Js.truthy(stun) and not is_boss and not guarded:
		D6AiCommon.stun(game, e, stun)
	var hitstop = src.get("hitstop")
	if D6Js.truthy(hitstop):
		apply_hitstop(game, minf(hitstop, t.boss[e.kind].hitstopCap) if is_boss else hitstop, e)

## Pousse un ennemi SANS le blesser (choc d'atterrissage du saut) : recul et étourdissement suivent
## les règles d'un coup (masse, blindé, Gardien, garde), mais rien n'est infligé — ni dégât, ni
## jauge de Super, ni proc « au toucher ». Ce n'est pas une attaque.
static func push_enemy(game: Dictionary, e: Dictionary, dir_x: float, dir_y: float, knockback: float, stun: float = 0.0) -> void:
	if e.dead or e.spawnT > 0.0 or _num(e, "invuln") > 0.0:
		return
	_apply_impact(game, e, {"kind": "move", "dirX": dir_x, "dirY": dir_y, "knockback": knockback, "stun": stun})

## Jauge de Super remplie par un coup du héros (hors sources exclues, hors ultime qui agit).
## `effective` : les PV réellement retirés — achever un ennemi à 1 PV ne remplit pas la jauge.
static func _charge_super(game: Dictionary, kind, effective: float) -> void:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var st: Dictionary = p.stats
	if is_player_source(kind) and not NO_SUPER_CHARGE.has(kind) and not D6KitSupers.acting(game):
		var before: float = p.superCharge
		# chargeDamage est donné pour l'arme de base : mis à l'échelle de l'arme portée, comme les
		# dégâts. Sans cela la jauge se remplissait en 90 coups à l'étage 1 et en 3 à l'étage 649
		# (les PV ennemis suivent l'arme) : invulnérable 40 % du temps en profondeur.
		var need: float = t["super"].chargeDamage * (st.weaponDamage / t.weaponBase)
		p.superCharge = minf(1.0, p.superCharge + (effective / need) * st.superChargeMult)
		if before < 1.0 and p.superCharge >= 1.0:
			D6State.emit(game, "superReady")

# Début de damageEnemy : le coup est-il arrêté avant tout calcul (immunité, pavois) ? Il est alors
# VU (événement), mais ne porte pas.
static func _hit_stopped(game: Dictionary, e: Dictionary, src: Dictionary, kind) -> bool:
	if _num(e, "invuln") > 0.0:
		# Boss en transition de phase : le coup est vu, mais ne porte pas.
		if kind == "melee" or kind == "strike" or kind == "skill":
			D6State.emit(game, "immune", {"x": e.x, "y": e.y})
		return true
	if D6FoeDefense.front_blocked(game, e, src):
		# Porte-pavois frappé de face : le coup sonne sur le pavois (même signal qu'une parade :
		# étincelles et tintement, au point de contact) et ne porte pas — ni dégât, ni recul, ni étourdissement.
		D6State.emit(game, "deflect", {"x": e.x + D6Trig.cos(e.face) * e.r, "y": e.y + D6Trig.sin(e.face) * e.r, "guard": true})
		return true
	return false

## Un coup du héros LUI-MÊME a porté : l'ennemi devient la cible désignée de la meute, et le vol de
## vie joue (celui du build, plus celui des griffes pendant la Forme du Damné).
static func _after_own_hit(game: Dictionary, e: Dictionary, kind, amount: float) -> void:
	var p: Dictionary = game.player
	p.markId = e.id
	p.markAt = game.time
	var steal: float = p.stats.lifesteal + D6KitSupers.form_lifesteal(game, kind)
	if steal > 0.0:
		heal_player(game, amount * steal, false)

## Inflige des dégâts à un ennemi. `src` : {kind, amount, dirX, dirY, knockback, hitstop,
## canCrit, stun}. Rend les dégâts réellement infligés.
static func damage_enemy(game: Dictionary, e: Dictionary, src: Dictionary) -> float:
	if e.dead or e.spawnT > 0.0:
		return 0.0
	var kind = src.get("kind")
	if _hit_stopped(game, e, src, kind):
		return 0.0
	var t: Dictionary = game.tuning
	var st: Dictionary = game.player.stats
	var amount := _scaled_amount(game, e, src)
	var crit_bonus := _crit_bonus(game, e, src)

	var crit := false
	if D6Js.truthy(src.get("canCrit")):
		var chance: float = t.combat.critChance + st.critChance + crit_bonus
		if D6Rng.rand(game.rng.combat) < chance:
			crit = true
			amount *= t.combat.critMult + st.critMult
	amount = maxf(1.0, D6Js.jround(amount))
	if src.get("cap") != null:
		amount = minf(amount, src.cap) # plafond du coup (Sentence capitale sur un Gardien)
	var hp_before: float = e.hp
	e.hp -= amount
	e.flash = HIT_FLASH
	e.lastHitAt = game.time
	if D6Js.truthy(src.get("dirX")) or D6Js.truthy(src.get("dirY")):
		e.hitDirX = src.get("dirX")
		e.hitDirY = src.get("dirY")

	_apply_impact(game, e, src)

	# L'overkill ne compte pas (télémétrie ET jauge de Super) : seuls les PV réellement retirés.
	var effective := minf(amount, maxf(0.0, hp_before))
	game.telemetry.damageDealt += effective
	if kind == "melee" or kind == "strike":
		game.telemetry.hitsLanded += 1.0

	_charge_super(game, kind, effective)
	if PROC_SOURCES.has(kind):
		_after_own_hit(game, e, kind, amount)

	D6State.emit(game, "hit", {
		"id": e.id, "x": e.x, "y": e.y, "amount": amount, "crit": crit, "kind": kind,
		"dirX": D6Js.nz(src.get("dirX"), 0.0), "dirY": D6Js.nz(src.get("dirY"), 0.0),
		"enemy": e.kind, "shake": D6Js.nz(src.get("shake"), 0.0),
	})

	if PROC_SOURCES.has(kind):
		_apply_hit_procs(game, e, src)
	if e.hp <= 0.0:
		kill_enemy(game, e, src)
	return amount

static func _apply_hit_procs(game: Dictionary, e: Dictionary, src: Dictionary) -> void:
	var p: Dictionary = game.player
	for pr in p.procs:
		if pr.get("on") != "hit" or not pr.sources.has(src.get("kind")):
			continue
		var cond = pr.get("when")
		if D6Js.truthy(cond) and not D6Js.truthy(src.get(cond)):
			continue
		var chance = pr.get("chance")
		if chance != null and chance < 1.0 and D6Rng.rand(game.rng.combat) >= chance:
			continue
		_apply_proc(game, pr, e, src)

## Déclenche les procs du moment `on` (tout sauf 'hit' et 'passive'). `target` : l'ennemi
## concerné s'il y en a un (tué, projeté) ; `ctx` : contexte du déclencheur (conditions `when`,
## quantité `amount` des effets « par unité »).
static func fire_procs(game: Dictionary, moment, target = null, ctx = null) -> void:
	var p: Dictionary = game.player
	for pr in p.procs:
		if pr.get("on") != moment:
			continue
		var cond = pr.get("when")
		if D6Js.truthy(cond) and not (ctx is Dictionary and D6Js.truthy(ctx.get(cond))):
			continue
		var chance = pr.get("chance")
		if chance != null and chance < 1.0 and D6Rng.rand(game.rng.combat) >= chance:
			continue
		_apply_proc(game, pr, target, ctx)

## Applique l'effet d'un proc déclenché : sur le héros, autour de lui, ou sur la cible `e`.
static func _apply_proc(game: Dictionary, pr: Dictionary, e, ctx) -> void:
	var p: Dictionary = game.player
	match pr.get("effect"):
		"heal":
			heal_player(game, pr.value, true)
		"surge":
			p.surge = maxf(p.surge, pr.duration)
			p.surgeMult = maxf(p.surgeMult, pr.value)
		"superCharge":
			if D6KitSupers.acting(game):
				return # jamais pendant un ultime : il ne se recharge pas lui-même
			var before: float = p.superCharge
			var unit := 1.0
			if D6Js.truthy(pr.get("perUnit")):
				unit = D6Js.nz(ctx.get("amount"), 0.0) if ctx is Dictionary else 0.0
			p.superCharge = minf(1.0, p.superCharge + pr.value * unit)
			if before < 1.0 and p.superCharge >= 1.0:
				D6State.emit(game, "superReady")
		"dashCharge":
			var max_dash: float = game.tuning.dash.charges + p.stats.dashChargesBonus
			if p.dashCharges >= max_dash:
				return
			p.dashCharges = minf(max_dash, p.dashCharges + pr.value)
			D6State.emit(game, "dashReady", {"charges": p.dashCharges})
		"gadgetCharge":
			_gadget_charges(game, pr.value, p.x, p.y)
		"nova":
			_hero_nova(game, pr)
		"around":
			_around_hero(game, pr)
		_:
			_apply_target_effect(game, pr.get("effect"), pr, e, ctx)

## Effet posé sur un ennemi. `src` : le coup qui l'a déclenché (garde contre le ré-étourdissement).
static func _apply_target_effect(game: Dictionary, effect, pr: Dictionary, e, src) -> void:
	var p: Dictionary = game.player
	if effect == "chain":
		_chain_lightning(game, e if e != null else p, pr) # sans cible : l'éclair part du héros
		return
	if effect == "gold":
		if e != null and D6Js.truthy(e.get("summoned")):
			return # invocations : ni or ni Âmes (pas de ferme tant que l'invocateur vit)
		var at: Dictionary = e if e != null else p
		var amount := D6Js.jround(pr.value)
		game.run.gold += amount
		D6State.emit(game, "gold", {"x": at.x, "y": at.y, "amount": amount})
		return
	if e == null:
		return
	match effect:
		"burn":
			e.burn = maxf(e.burn, pr.duration)
			e.burnDps = maxf(e.burnDps, pr.value)
		"chill":
			e.chill = maxf(e.chill, pr.duration)
			# Borné : un ennemi ralenti reste un ennemi qui avance (jamais de vitesse négative).
			var cur = e.get("chillMult")
			if not D6Js.truthy(cur):
				cur = 1.0
			e.chillMult = minf(cur, maxf(game.tuning.combat.minChillMult, 1.0 - pr.value))
		"vuln":
			e.vuln = maxf(e.vuln, pr.duration)
			e.vulnMult = maxf(e.vulnMult, pr.value)
		"stun":
			# Mêmes règles que damageEnemy : jamais un Gardien, et la garde tient contre un coup d'arme.
			if D6Js.truthy(e.get("boss")) or e.dead:
				return
			if _num(e, "guard") > 0.0 and src is Dictionary and game.tuning.combat.stunGuardSources.has(src.get("kind")):
				return
			D6AiCommon.stun(game, e, pr.value)
		"blast":
			spawn_hazard(game, {
				"shape": "circle", "x": e.x, "y": e.y, "r": pr.radius, "delay": game.tuning.combat.procBlastDelay, "damage": pr.value,
				"hitsPlayer": false, "hitsEnemies": true, "kind": "sinBlast", "sourceId": 0.0,
			})
		"cull":
			# Achève un ennemi affaibli (jamais un Gardien) : la mort porte la marque de l'éclair.
			if not D6Js.truthy(e.get("boss")) and not e.dead and e.hp / e.maxHp <= pr.value:
				kill_enemy(game, e, {"kind": "chain"})
		_:
			pass

## Déflagration autour du héros : dégâts à tout ennemi dans le rayon, gel facultatif (`chill` s).
static func _hero_nova(game: Dictionary, pr: Dictionary) -> void:
	var p: Dictionary = game.player
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = pr.radius + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) < rr * rr:
			damage_enemy(game, e, {"kind": "blast", "amount": pr.value, "dirX": 0.0, "dirY": 0.0, "canCrit": false})
			if D6Js.truthy(pr.get("chill")):
				e.chill = maxf(e.chill, pr.chill)
				var cur: float = e.chillMult if D6Js.truthy(e.get("chillMult")) else 1.0
				e.chillMult = minf(cur, game.tuning.combat.novaChillMult)
	D6State.emit(game, "dashNova", {"x": p.x, "y": p.y, "r": pr.radius})

## Onde sans dégâts autour du héros : pose l'effet de cible `apply` sur tout ennemi dans le rayon.
static func _around_hero(game: Dictionary, pr: Dictionary) -> void:
	var p: Dictionary = game.player
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = pr.radius + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) < rr * rr:
			_apply_target_effect(game, pr.get("apply"), pr, e, null)
	D6State.emit(game, "dashNova", {"x": p.x, "y": p.y, "r": pr.radius})

static func _chain_lightning(game: Dictionary, origin: Dictionary, pr: Dictionary) -> void:
	var cur: Dictionary = origin
	var hit: Array = [origin.get("id")] # le héros (éclair sans cible) n'a pas d'identifiant
	var i := 0.0
	while i < pr.bounces:
		i += 1.0
		var best = null
		var best_d: float = pr.range * pr.range
		for o in game.enemies:
			if o.dead or o.spawnT > 0.0 or _has_id(hit, o.id):
				continue
			var d := D6Geo.dist2(cur.x, cur.y, o.x, o.y)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			break
		D6State.emit(game, "chain", {"x0": cur.x, "y0": cur.y, "x1": best.x, "y1": best.y})
		hit.append(best.id)
		damage_enemy(game, best, {"kind": "chain", "amount": pr.value, "canCrit": false})
		if not best.dead:
			_apply_hit_procs(game, best, {"kind": "chainHit"})
		cur = best

## Âmes (PERMANENTES, profil) : jamais dans l'arène d'essai, jamais pour une invocation.
static func _grant_souls(game: Dictionary, e: Dictionary, elite: bool) -> void:
	var t: Dictionary = game.tuning
	var tel: Dictionary = game.telemetry
	if not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice")) and not D6Js.truthy(e.get("summoned")) and not D6Js.truthy(e.get("boss")):
		var souls: float = t.progression.souls.elite if elite else t.progression.souls.kill
		game.meta.souls += souls
		game.meta.stats.kills += 1.0
		tel.soulsEarned += souls
		if elite:
			D6State.emit(game, "souls", {"x": e.x, "y": e.y, "amount": souls})
		Arbre.gain(game, "elite" if elite else "kill") # expérience de classe : mêmes conditions que les Âmes

## Butin d'or (les boss ont leur propre récompense, gérée par la salle).
static func _drop_gold(game: Dictionary, e: Dictionary, elite: bool) -> void:
	var t: Dictionary = game.tuning
	if not D6Js.truthy(e.get("boss")) and not D6Js.truthy(e.get("summoned")):
		var def: Dictionary = t.enemies[e.kind]
		var lo: float = def.gold[0]
		var hi: float = def.gold[1]
		var amount := lo + floorf(D6Rng.rand(game.rng.gen) * (hi - lo + 1.0))
		if elite:
			amount *= t.elite.goldMult
		amount = D6Js.jround(amount * game.player.stats.goldFindMult)
		if amount > 0.0:
			spawn_pickup(game, "gold", e.x, e.y, amount)

## Charges rendues à CHAQUE gadget équipé (D6Loadout.grant_gadget_charges) ; un seul événement,
## au nom du premier emplacement qui en a gagné. Rien si tous sont pleins (ou sans gadget).
static func _gadget_charges(game: Dictionary, amount, x: float, y: float) -> void:
	var slot := D6Loadout.grant_gadget_charges(game, amount)
	if slot >= 0:
		D6State.emit(game, "gadgetCharge", {"x": x, "y": y, "charges": game.player.slots[slot].charges, "slot": float(slot)})

## Mort d'un élite ou d'un boss : charge de gadget, gel imposé, explosion de l'élite ardent.
static func _kill_rewards(game: Dictionary, e: Dictionary, elite: bool) -> void:
	var t: Dictionary = game.tuning
	if elite:
		_gadget_charges(game, null, e.x, e.y) # chaque gadget équipé : son chargeOnEliteKill
		force_hitstop(game, t.killHitstop.elite)
	if D6Js.truthy(e.get("boss")):
		force_hitstop(game, t.killHitstop.boss)
	if e.get("eliteMod") == "ardent":
		var m: Dictionary = t.elite.mods.ardent
		spawn_hazard(game, {
			"shape": "circle", "x": e.x, "y": e.y, "r": m.deathBlastRadius, "delay": m.deathBlastDelay,
			"damage": m.deathBlastDamage * e.dmgScale, "hitsPlayer": true, "hitsEnemies": false, "kind": "fireBlast", "sourceId": 0.0,
		})

## Procs « à la mort d'un ennemi », soin et or par ennemi tué.
static func _kill_procs(game: Dictionary, e: Dictionary) -> void:
	var p: Dictionary = game.player
	fire_procs(game, "kill", e)
	if _num(p.stats, "healOnKill") > 0.0:
		heal_player(game, p.stats.healOnKill, true)
	var extra_gold := _num(p.stats, "extraGoldOnKill")
	if extra_gold > 0.0 and not D6Js.truthy(e.get("summoned")):
		game.run.gold += extra_gold
		D6State.emit(game, "gold", {"x": e.x, "y": e.y, "amount": extra_gold})

static func kill_enemy(game: Dictionary, e: Dictionary, src = null) -> void:
	if e.dead:
		return
	e.dead = true
	e.hp = 0.0
	e.tele = null
	var tel: Dictionary = game.telemetry
	tel.kills += 1.0
	tel.killTimes.append({"kind": e.kind, "life": game.time - e.bornAt})
	var elite := D6Js.truthy(e.get("eliteMod"))
	_grant_souls(game, e, elite)
	var src_kind = src.get("kind") if src != null else null
	D6State.emit(game, "kill", {
		"id": e.id, "x": e.x, "y": e.y, "r": e.r, "enemy": e.kind, "elite": elite,
		"boss": D6Js.truthy(e.get("boss")), "kind": D6Js.nz(src_kind, "none"),
	})
	_drop_gold(game, e, elite)
	_kill_rewards(game, e, elite)
	_kill_procs(game, e)

static func heal_player(game: Dictionary, amount: float, show) -> void:
	var p: Dictionary = game.player
	if p.state == "dead" or amount <= 0.0:
		return
	var before: float = p.hp
	p.hp = minf(p.maxHp, p.hp + amount)
	if D6Js.truthy(show) and p.hp - before >= 1.0:
		D6State.emit(game, "heal", {"x": p.x, "y": p.y, "amount": D6Js.jround(p.hp - before)})
	# Trop-plein : les PV soignés au-delà du maximum nourrissent les procs « overheal ».
	var over: float = before + amount - p.maxHp
	if over > 0.0 and p.get("procs") != null:
		fire_procs(game, "overheal", null, {"amount": over})

## Coup reçu pendant les i-frames : esquivé — et compté comme tel s'il l'est grâce à un dash.
static func _dodge(game: Dictionary, src: Dictionary) -> void:
	var p: Dictionary = game.player
	var src_id = src.get("id")
	if p.dodgeIframes > 0.0 and not _has_id(p.dodgedIds, src_id):
		p.dodgedIds.append(src_id)
		game.telemetry.dodges += 1.0
		# Esquive parfaite : la jauge de Super grimpe et le dash se recharge plus vite.
		var d: Dictionary = game.tuning.dash
		var before: float = p.superCharge
		if not D6KitSupers.acting(game): # un ultime qui agit ne se recharge pas
			p.superCharge = minf(1.0, p.superCharge + d.perfectDodgeSuper)
		if before < 1.0 and p.superCharge >= 1.0:
			D6State.emit(game, "superReady")
		p.dashRecharge += d.perfectDodgeRefund
		D6State.emit(game, "dodge", {"x": p.x, "y": p.y})
		fire_procs(game, "dodge")

## Inflige des dégâts au héros. Rend true si le coup a porté. Pendant les i-frames, le coup
## est esquivé — et compté comme tel s'il était évité grâce à un dash.
static func damage_player(game: Dictionary, amount: float, src: Dictionary) -> bool:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	if p.state == "dead" or D6Js.truthy(game.get("godMode")):
		return false
	if p.iframes > 0.0 or p.state == "super":
		_dodge(game, src)
		return false
	var src_kind = src.get("kind")
	var armor := D6Geo.clampv(p.stats.armor, 0.0, t.combat.armorCap)
	var dmg := maxf(1.0, D6Js.jround(amount * (1.0 - armor)))
	p.hp -= dmg
	p.iframes = t.player.hurtIframes
	p.dodgeIframes = 0.0
	p.hurtFlash = HURT_FLASH
	# Une blessure : la salle n'est plus « sans une égratignure », la série sans blessure retombe.
	if D6Js.truthy(game.get("room")):
		game.room.hurt = true
	game.run.streak = 0.0
	force_hitstop(game, t.player.hurtHitstop)
	var tel: Dictionary = game.telemetry
	tel.damageTaken += dmg
	tel.hitsTaken += 1.0
	D6State.emit(game, "playerHurt", {
		"x": p.x, "y": p.y, "amount": dmg, "source": src_kind,
		"srcX": D6Js.nz(src.get("x"), p.x), "srcY": D6Js.nz(src.get("y"), p.y),
	})
	if p.hp <= 0.0:
		p.hp = 0.0
		p.state = "dead"
		p.stateTime = 0.0
		p.attack = null
		tel.deaths += 1.0
		tel.deathCauses[src_kind] = D6Js.nz(tel.deathCauses.get(src_kind), 0.0) + 1.0
		D6State.emit(game, "playerDeath", {"x": p.x, "y": p.y, "source": src_kind})
	return true

static func spawn_pickup(game: Dictionary, kind, x: float, y: float, value, extra = null) -> Dictionary:
	var a: float = D6Rng.rand(game.rng.gen) * PI * 2.0
	var room: Dictionary = game.tuning.room
	var s: float = room.pickupSpeed + D6Rng.rand(game.rng.gen) * room.pickupSpeedSpread
	var pk := {
		"id": D6State.new_id(game), "kind": kind, "x": x, "y": y, "vx": D6Trig.cos(a) * s, "vy": D6Trig.sin(a) * s,
		"r": room.goldRadius if kind == "gold" else room.pickupRadius, "value": value, "age": 0.0,
	}
	if extra != null:
		pk.merge(extra, true)
	game.pickups.append(pk)
	return pk

## Zone de danger télégraphiée : visible pendant `delay`, puis frappe une fois.
## shape 'circle' {x, y, r} | 'line' {x, y, angle, length, width} | 'ring' {x, y, r, inner}.
static func spawn_hazard(game: Dictionary, h: Dictionary) -> Dictionary:
	var hz := {
		"id": D6State.new_id(game),
		"shape": "circle",
		"angle": 0.0,
		"length": 0.0,
		"width": 0.0,
		"inner": 0.0,
		"t": 0.0,
		"sourceId": 0.0,
		"hitsPlayer": true,
		"hitsEnemies": false,
		"done": false,
	}
	hz.merge(h, true)
	game.hazards.append(hz)
	D6State.emit(game, "hazard", {"id": hz.id, "kind": hz.get("kind"), "x": hz.get("x"), "y": hz.get("y")})
	return hz
