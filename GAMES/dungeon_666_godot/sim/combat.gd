class_name D6Combat
extends RefCounted
## Portage de src/sim/combat.mjs.
## Résolution des dégâts — UN SEUL chemin pour toucher un ennemi (damage_enemy) et UN SEUL
## pour toucher le héros (damage_player). Les bénédictions n'exécutent pas de code : elles
## déclarent des « procs » (données) que ce module interprète. Pas d'import circulaire.

# Sources de dégâts du héros qui déclenchent les procs « au toucher ».
const PROC_SOURCES := ["melee", "strike", "skill", "gadget", "super"]
# Sources qui ne remplissent pas la jauge de Super (sinon le Super se recharge lui-même).
const NO_SUPER_CHARGE := ["super", "burn", "blast", "chain"]
const ARMOR_CAP := 0.6
const HIT_FLASH := 0.1 # s : éclat d'un ennemi touché
const HURT_FLASH := 0.35 # s : éclat du héros touché
const BOSS_KNOCKBACK_MULT := 0.15
const KILL_BLAST_DELAY := 0.12 # s : télégraphe de l'explosion d'un proc « blast »
const PICKUP_SPEED_MIN := 80.0
const PICKUP_SPEED_SPAN := 120.0
const GOLD_RADIUS := 6.0
const PICKUP_RADIUS := 10.0

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
		if kind == "super":
			amount *= D6Js.nz(st.get("superDamageMult"), 1.0)
	if e.get("eliteMod") == "blinde":
		amount *= t.elite.mods.blinde.damageTakenMult
	if e.stun > 0.0:
		amount *= t.combat.stunDamageTakenMult
	if e.vuln > 0.0:
		amount *= 1.0 + e.vulnMult
	if _num(e, "exposed") > 0.0:
		amount *= 1.0 + _or_nan(e.get("exposedMult")) # point faible d'un Gardien (boss_common.expose)
	return amount

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
			kb *= BOSS_KNOCKBACK_MULT
		var cur2: float = e.kvx * e.kvx + e.kvy * e.kvy
		if kb * kb > cur2:
			e.kvx = _or_nan(src.get("dirX")) * kb
			e.kvy = _or_nan(src.get("dirY")) * kb
	# En garde (il sort d'un étourdissement) : un coup d'arme blesse et repousse, sans ré-étourdir.
	var guarded: bool = _num(e, "guard") > 0.0 and t.combat.stunGuardSources.has(kind)
	var stun = src.get("stun")
	if D6Js.truthy(stun) and not is_boss and not guarded:
		e.stun = maxf(e.stun, stun)
		e.tele = null
		e.state = "stunned"
		e.stateTime = 0.0
	var hitstop = src.get("hitstop")
	if D6Js.truthy(hitstop):
		apply_hitstop(game, minf(hitstop, t.boss[e.kind].hitstopCap) if is_boss else hitstop, e)

## Jauge de Super remplie par un coup du héros (hors sources exclues, hors Super en cours).
static func _charge_super(game: Dictionary, kind, amount: float, hp_before: float) -> void:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var st: Dictionary = p.stats
	if is_player_source(kind) and not NO_SUPER_CHARGE.has(kind) and p.state != "super":
		var before: float = p.superCharge
		# L'overkill ne compte pas : achever un ennemi à 1 PV ne remplit pas la jauge.
		var effective := minf(amount, maxf(0.0, hp_before))
		# chargeDamage est donné pour l'arme de base : mis à l'échelle de l'arme portée, comme les
		# dégâts. Sans cela la jauge se remplissait en 90 coups à l'étage 1 et en 3 à l'étage 649
		# (les PV ennemis suivent l'arme) : invulnérable 40 % du temps en profondeur.
		var need: float = t["super"].chargeDamage * (st.weaponDamage / t.weaponBase)
		p.superCharge = minf(1.0, p.superCharge + (effective / need) * st.superChargeMult)
		if before < 1.0 and p.superCharge >= 1.0:
			D6State.emit(game, "superReady")

## Inflige des dégâts à un ennemi. `src` : {kind, amount, dirX, dirY, knockback, hitstop,
## canCrit, stun}. Rend les dégâts réellement infligés.
static func damage_enemy(game: Dictionary, e: Dictionary, src: Dictionary) -> float:
	if e.dead or e.spawnT > 0.0:
		return 0.0
	var kind = src.get("kind")
	if _num(e, "invuln") > 0.0:
		# Boss en transition de phase : le coup est vu, mais ne porte pas.
		if kind == "melee" or kind == "strike" or kind == "skill":
			D6State.emit(game, "immune", {"x": e.x, "y": e.y})
		return 0.0
	var t: Dictionary = game.tuning
	var st: Dictionary = game.player.stats
	var amount := _scaled_amount(game, e, src)

	var crit := false
	if D6Js.truthy(src.get("canCrit")):
		var chance: float = t.combat.critChance + st.critChance
		if D6Rng.rand(game.rng.combat) < chance:
			crit = true
			amount *= t.combat.critMult + st.critMult
	amount = maxf(1.0, D6Js.jround(amount))
	var hp_before: float = e.hp
	e.hp -= amount
	e.flash = HIT_FLASH
	e.lastHitAt = game.time
	if D6Js.truthy(src.get("dirX")) or D6Js.truthy(src.get("dirY")):
		e.hitDirX = src.get("dirX")
		e.hitDirY = src.get("dirY")

	_apply_impact(game, e, src)

	var tel: Dictionary = game.telemetry
	tel.damageDealt += amount
	if kind == "melee" or kind == "strike":
		tel.hitsLanded += 1.0

	_charge_super(game, kind, amount, hp_before)
	if st.lifesteal > 0.0 and PROC_SOURCES.has(kind):
		heal_player(game, amount * st.lifesteal, false)

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
		var chance = pr.get("chance")
		if chance != null and chance < 1.0 and D6Rng.rand(game.rng.combat) >= chance:
			continue
		match pr.get("effect"):
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
			"chain":
				_chain_lightning(game, e, pr)
			"gold":
				if D6Js.truthy(e.get("summoned")):
					continue # invocations : ni or ni Âmes (pas de ferme tant que l'invocateur vit)
				game.run.gold += pr.value
				D6State.emit(game, "gold", {"x": e.x, "y": e.y, "amount": pr.value})
			_:
				pass

static func _chain_lightning(game: Dictionary, origin: Dictionary, pr: Dictionary) -> void:
	var cur: Dictionary = origin
	var hit: Array = [origin.id]
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

## Mort d'un élite ou d'un boss : charge de gadget, gel imposé, explosion de l'élite ardent.
static func _kill_rewards(game: Dictionary, e: Dictionary, elite: bool) -> void:
	var t: Dictionary = game.tuning
	if elite:
		var p: Dictionary = game.player
		var max_g: float = t.gadget.chargesPerSection + p.stats.gadgetChargesBonus
		if p.gadgetCharges < max_g:
			p.gadgetCharges = minf(max_g, p.gadgetCharges + t.gadget.chargeOnEliteKill)
			D6State.emit(game, "gadgetCharge", {"x": e.x, "y": e.y, "charges": p.gadgetCharges})
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
	for pr in p.procs:
		if pr.get("on") != "kill":
			continue
		var effect = pr.get("effect")
		if effect == "heal":
			heal_player(game, pr.value, true)
		if effect == "blast":
			spawn_hazard(game, {
				"shape": "circle", "x": e.x, "y": e.y, "r": pr.radius, "delay": KILL_BLAST_DELAY, "damage": pr.value,
				"hitsPlayer": false, "hitsEnemies": true, "kind": "sinBlast", "sourceId": 0.0,
			})
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
		p.superCharge = minf(1.0, p.superCharge + d.perfectDodgeSuper)
		if before < 1.0 and p.superCharge >= 1.0:
			D6State.emit(game, "superReady")
		p.dashRecharge += d.perfectDodgeRefund
		D6State.emit(game, "dodge", {"x": p.x, "y": p.y})

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
	var armor := D6Geo.clampv(p.stats.armor, 0.0, ARMOR_CAP)
	var dmg := maxf(1.0, D6Js.jround(amount * (1.0 - armor)))
	p.hp -= dmg
	p.iframes = t.player.hurtIframes
	p.dodgeIframes = 0.0
	p.hurtFlash = HURT_FLASH
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
	var s: float = PICKUP_SPEED_MIN + D6Rng.rand(game.rng.gen) * PICKUP_SPEED_SPAN
	var pk := {
		"id": D6State.new_id(game), "kind": kind, "x": x, "y": y, "vx": D6Trig.cos(a) * s, "vy": D6Trig.sin(a) * s,
		"r": GOLD_RADIUS if kind == "gold" else PICKUP_RADIUS, "value": value, "age": 0.0,
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
