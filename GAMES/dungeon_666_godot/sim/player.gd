class_name D6Player
extends RefCounted
## Portage de src/sim/player.mjs.
## Le héros : machine à états (free | attack | dash | cast | super | dead), tampon d'input,
## annulations (cancels). Règle de feel n°1 : le DASH annule presque tout, tout de suite.
##
## KITS : le code est choisi par le `kind` de l'entrée équipée (kits). Le kit d'origine
## (Lame, Lance, Nova, Colère) est joué ICI, à l'identique ; les autres par kit_* :
##   arme 'ranged'      -> kit_shots.fire_weapon_shots (traits au début de l'actif, pas de balayage)
##   compétence ≠ lance -> kit_skills (chain, bond, brasier, volee)
##   gadget ≠ nova      -> kit_gadgets (bombe, piege, totem)
##   Super ≠ colere     -> kit_supers (sentence, nuee)
## Les tirs et zones posés par le héros vivent dans la salle (kit_common.kit_store).
##
## InputFrame attendu (produit par l'entrée, ou par un bot) :
##   { moveX, moveY,            // [-1, 1], norme <= 1 (analogique)
##     aimX, aimY,              // visée manuelle (0, 0 = visée assistée)
##     attack,                  // maintenu : enchaîne le combo
##     attackPressed, dashPressed, skillPressed, gadgetPressed, superPressed,  // fronts
##     skillAimX, skillAimY }   // visée de la compétence au relâcher (0, 0 = assistée)

const PRIORITY := ["dash", "super", "skill", "attack"]

## `ids.includes(id)` : comparaison par `==` (Array.has distingue 1 de 1.0, JavaScript non).
static func _has_id(ids: Array, id) -> bool:
	for v in ids:
		if v == id:
			return true
	return false

static func max_dash_charges(game: Dictionary) -> float:
	return game.tuning.dash.charges + game.player.stats.dashChargesBonus

static func _buffer_action(p: Dictionary, action: String, t: float, aim_x: float = 0.0, aim_y: float = 0.0) -> void:
	var cur = p.buffer.action
	# Un dash en attente n'est jamais écrasé par une action moins prioritaire.
	if D6Js.truthy(cur) and p.buffer.t > 0.0 and PRIORITY.find(cur) < PRIORITY.find(action):
		return
	p.buffer.action = action
	p.buffer.t = t
	p.buffer.aimX = aim_x
	p.buffer.aimY = aim_y

## Vrai si un dash peut partir maintenant (utilisé aussi pour annuler le gel d'impact).
static func can_dash(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.dashCharges < 1.0:
		return false
	if p.state == "free" or p.state == "attack" or p.state == "cast":
		return true
	if p.state == "dash":
		return p.dashT <= game.tuning.dash.duration * game.tuning.dash.chainFrom # re-dash quand il reste moins de cette part du dash
	return false

static func _can_attack(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.state == "free":
		return true
	# Frappe de dash : attaquer en fin de dash coupe la ruée et frappe tout de suite.
	if p.state == "dash":
		return p.dashT <= game.tuning.dash.duration * game.tuning.dash.strikeCancelFrom
	if p.state != "attack" or p.attack.phase != "recovery":
		return false
	# Le coup suivant n'annule qu'une PARTIE de la récupération (le finisher engage) ; seul le
	# dash annule tout, tout de suite.
	var a: Dictionary = p.attack
	var t: Dictionary = game.tuning
	# Part de récupération propre au coup (armes) ou celle de la Lame ; D9 l'allonge ou l'abrège.
	var base: float = t.comboCancelFrom.strike if a.strike else _cancel_from(a, t)
	var from: float = minf(1.0, base * D6Js.nz(t.player.get("cancelMult"), 1.0))
	return a.t >= a.dur.recovery * from

## a.def.cancelFrom ?? t.comboCancelFrom.hits[a.index] ?? 1 (un index hors du tableau rend 1).
static func _cancel_from(a: Dictionary, t: Dictionary) -> float:
	var own = a.def.get("cancelFrom")
	if own != null:
		return own
	var hits: Array = t.comboCancelFrom.hits
	var idx := int(a.index)
	if float(idx) == float(a.index) and idx >= 0 and idx < hits.size() and hits[idx] != null:
		return hits[idx]
	return 1.0

static func _can_skill(p: Dictionary) -> bool:
	if p.skillCd > 0.0:
		return false
	if p.state == "free":
		return true
	return p.state == "attack" and p.attack.phase == "recovery"

static func _can_super(p: Dictionary) -> bool:
	return p.superCharge >= 1.0 and (p.state == "free" or p.state == "attack" or p.state == "cast" or p.state == "dash")

## Une action ne mérite le tampon que si elle peut partir pendant sa fenêtre : marteler un dash
## sans charge, ou toucher un Super pas prêt, ne doit JAMAIS avaler la frappe qui suit.
static func _feasible_soon(game: Dictionary, action: String, window: float) -> bool:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	if action == "dash":
		if p.dashCharges >= 1.0:
			return true
		return t.dash.recharge * p.stats.dashRechargeMult - p.dashRecharge <= window
	if action == "super":
		return p.superCharge >= 1.0
	if action == "skill":
		return p.skillCd <= window
	return true

## `input.clé || 0` : un champ absent, nul ou faux vaut 0.
static func _num(input: Dictionary, key: String) -> float:
	var v = input.get(key)
	return float(v) if D6Js.truthy(v) else 0.0

## Lit les fronts de l'InputFrame et les met en tampon. Rend true si dash est en attente.
static func read_input(game: Dictionary, input: Dictionary) -> bool:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var buf: float = t.player.inputBuffer
	var lock_buf: float = D6Js.nz(t.player.get("attackBuffer"), buf) # attaque et Lance attendent la fin d'un coup engagé
	var mx: float = _num(input, "moveX")
	var my: float = _num(input, "moveY")
	var ml: float = sqrt(mx * mx + my * my)
	if ml > 1.0:
		mx /= ml
		my /= ml
	p.moveX = mx
	p.moveY = my
	p.manualAimX = _num(input, "aimX")
	p.manualAimY = _num(input, "aimY")
	p.attackHeld = D6Js.truthy(input.get("attack"))
	if D6Js.truthy(input.get("attackPressed")):
		_buffer_action(p, "attack", lock_buf)
	if D6Js.truthy(input.get("skillPressed")) and _feasible_soon(game, "skill", lock_buf):
		_buffer_action(p, "skill", lock_buf, _num(input, "skillAimX"), _num(input, "skillAimY"))
	if D6Js.truthy(input.get("superPressed")) and _feasible_soon(game, "super", buf):
		_buffer_action(p, "super", buf)
	if D6Js.truthy(input.get("dashPressed")) and _feasible_soon(game, "dash", buf):
		_buffer_action(p, "dash", buf)
	if D6Js.truthy(input.get("gadgetPressed")):
		use_gadget(game)
	return p.buffer.action == "dash" and p.buffer.t > 0.0

static func update_player(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	# Tirs et zones posés par le héros (kits) : ils continuent pendant un gel LOCAL (D8).
	var room = game.get("room")
	if room != null and room.get("kitFx") != null:
		D6KitShots.update_shots(game, dt)
		D6KitZones.update_zones(game, dt)
	if p.freeze > 0.0:
		# Gel d'impact LOCAL (D8) : le héros se fige comme en mode global, mais seul.
		p.freeze = maxf(0.0, p.freeze - dt)
		return
	p.stateTime += dt
	if p.state == "dead":
		p.vx *= 0.85
		p.vy *= 0.85
		return
	_tick_timers(game, dt)
	if p.buffer.t > 0.0:
		_try_buffered(game)
		p.buffer.t -= dt
		if p.buffer.t <= 0.0:
			p.buffer.action = null
	# Attaque maintenue : enchaîne le combo sans re-taper (confort mobile).
	if p.attackHeld and not D6Js.truthy(p.buffer.action) and _can_attack(game) and p.state != "dash":
		_start_attack(game)
	_update_state(game, dt)
	D6Physics.move_circle(game.room, p, p.vx * dt, p.vy * dt)

## Le `switch (p.state)` de updatePlayer.
static func _update_state(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	match p.state:
		"free":
			_locomotion(game, dt, t.player.speed * p.stats.moveSpeedMult)
			if absf(p.manualAimX) + absf(p.manualAimY) > 0.15:
				p.facing = D6Trig.atan2(p.manualAimY, p.manualAimX)
			elif p.moveX * p.moveX + p.moveY * p.moveY > 0.04:
				p.facing = D6Trig.atan2(p.moveY, p.moveX)
		"attack":
			_update_attack(game, dt)
		"dash":
			_update_dash(game, dt)
		"cast":
			_update_cast(game, dt)
		"super":
			_update_super(game, dt)

static func _tick_timers(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	p.iframes = maxf(0.0, p.iframes - dt)
	p.dodgeIframes = maxf(0.0, p.dodgeIframes - dt)
	p.hurtFlash = maxf(0.0, p.hurtFlash - dt)
	p.skillCd = maxf(0.0, p.skillCd - dt)
	p.strikeWindow = maxf(0.0, p.strikeWindow - dt)
	# Élan passager (proc « surge ») : il s'éteint avec son bonus.
	if p.surge > 0.0:
		p.surge = maxf(0.0, p.surge - dt)
		if p.surge <= 0.0:
			p.surgeMult = 0.0
	if p.state != "attack":
		p.comboTimer += dt
	var max_c: float = max_dash_charges(game)
	if p.dashCharges < max_c:
		p.dashRecharge += dt
		var need: float = t.dash.recharge * p.stats.dashRechargeMult
		if p.dashRecharge >= need:
			p.dashRecharge -= need
			p.dashCharges += 1.0
			D6State.emit(game, "dashReady", {"charges": p.dashCharges})
	else:
		p.dashRecharge = 0.0

static func _try_buffered(game: Dictionary) -> void:
	var p: Dictionary = game.player
	match p.buffer.action:
		"dash":
			if can_dash(game):
				p.buffer.action = null
				_start_dash(game)
		"super":
			if _can_super(p):
				p.buffer.action = null
				_start_super(game)
		"skill":
			if _can_skill(p):
				var ax: float = p.buffer.aimX
				var ay: float = p.buffer.aimY
				p.buffer.action = null
				_start_cast(game, ax, ay)
		"attack":
			if _can_attack(game):
				p.buffer.action = null
				_start_attack(game)

static func _locomotion(game: Dictionary, dt: float, speed: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning.player
	var tx: float = p.moveX * speed
	var ty: float = p.moveY * speed
	var accelerating: bool = p.moveX * p.moveX + p.moveY * p.moveY > 0.0001
	var rate: float = (speed / t.accelTime if accelerating else speed / t.decelTime) * dt
	var dx: float = tx - p.vx
	var dy: float = ty - p.vy
	var d: float = sqrt(dx * dx + dy * dy)
	if d <= rate:
		p.vx = tx
		p.vy = ty
	else:
		p.vx += (dx / d) * rate
		p.vy += (dy / d) * rate

# ---------------------------------------------------------------- attaque (combo / frappe de dash)

## Part de la vitesse gardée pendant un coup : player.attackMoveMult (D9), modulée par l'arme
## (moveMult : dagues mobiles ; hache, maillet, arc et arbalète lents), jamais au-delà de la course.
static func _attack_move_factor(t: Dictionary) -> float:
	var weapon = t.get("weapon")
	var m = weapon.get("moveMult") if weapon != null else null
	if m == null:
		return t.player.attackMoveMult
	return minf(1.0, t.player.attackMoveMult * m)

static func _phase_durations(def: Dictionary, speed_mult: float) -> Dictionary:
	return {"startup": def.startup / speed_mult, "active": def.active / speed_mult, "recovery": def.recovery / speed_mult}

static func _start_attack(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var strike: bool = p.strikeWindow > 0.0 or p.state == "dash"
	if p.state == "dash":
		D6State.emit(game, "cancel", {"from": "dash"})
	var index: float = 0.0
	if not strike:
		if p.state == "attack":
			index = fmod(p.attack.index + 1.0, float(t.combo.size()))
		elif p.comboTimer <= t.comboResetTime:
			index = p.comboIndex
	# RÉFÉRENCE vers l'entrée de game.tuning (jamais une copie).
	var def: Dictionary = t.dashStrike if strike else t.combo[int(index)]
	# Visée assistée : portée de l'arme à distance (aimRange), sinon celle de la mêlée.
	var weapon = t.get("weapon")
	var aim: Dictionary = D6Aim.compute_aim(game, p.manualAimX, p.manualAimY, weapon.get("aimRange") if weapon != null else null)
	p.swingSeq += 1.0
	p.attack = {
		"def": def,
		"index": index,
		"strike": strike,
		"finisher": (not strike) and index == float(t.combo.size()) - 1.0, # dernier coup du combo (procs `when: 'finisher'`)
		"phase": "startup",
		"t": 0.0,
		"dur": _phase_durations(def, p.stats.attackSpeedMult),
		"dirX": aim.x,
		"dirY": aim.y,
		"angle": D6Trig.atan2(aim.y, aim.x),
		"targetId": aim.targetId,
		"targetDist": aim.targetDist,
		"hitIds": [],
		"swingId": p.swingSeq,
		"lungeV": 0.0,
	}
	p.strikeWindow = 0.0
	p.facing = p.attack.angle
	if D6Js.truthy(aim.targetId):
		p.lastTargetId = aim.targetId
		p.lastTargetAt = game.time
	p.state = "attack"
	p.stateTime = 0.0
	game.telemetry.attacks += 1.0
	D6State.emit(game, "attackStart", {"index": index, "strike": strike, "angle": p.attack.angle})

static func _update_attack(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var a: Dictionary = p.attack
	var shot = a.def.get("shot")
	a.t += dt
	# Mouvement résiduel + élan (lunge) pendant l'actif.
	var slow: float = t.player.speed * p.stats.moveSpeedMult * _attack_move_factor(t)
	var vx: float = p.moveX * slow
	var vy: float = p.moveY * slow
	if a.phase == "startup" and a.t >= a.dur.startup:
		a.phase = "active"
		a.t -= a.dur.startup
		a.lungeV = _lunge_distance(game, a) / maxf(1e-3, a.dur.active)
		var kit = game.get("kit")
		D6State.emit(game, "swing", {"x": p.x, "y": p.y, "angle": a.angle, "arc": a.def.arc * D6Data.DEG, "range": a.def.range, "index": a.index, "strike": a.strike, "weapon": kit.get("weaponType") if kit != null else null, "ranged": D6Js.truthy(shot)})
		# Arme à distance : les traits partent au début de l'actif (pas de balayage ni de parade).
		if D6Js.truthy(shot):
			D6KitShots.fire_weapon_shots(game, a)
	if a.phase == "active":
		vx += a.dirX * a.lungeV
		vy += a.dirY * a.lungeV
		if not D6Js.truthy(shot):
			_sweep_hits(game, a)
		if a.t >= a.dur.active:
			a.phase = "recovery"
			a.t -= a.dur.active
	if a.phase == "recovery" and a.t >= a.dur.recovery:
		# La frappe de dash compte comme le coup 1 : on enchaîne directement sur le coup 2.
		p.comboIndex = 1.0 if a.strike else fmod(a.index + 1.0, float(t.combo.size()))
		p.comboTimer = 0.0
		p.attack = null
		p.state = "free"
		p.stateTime = 0.0
	p.vx = vx
	p.vy = vy

## Élan « aimanté » : on s'arrête au contact de la cible au lieu de la traverser, et on
## allonge un peu l'élan si elle est juste hors de portée (indulgence mobile).
static func _lunge_distance(game: Dictionary, a: Dictionary) -> float:
	var p: Dictionary = game.player
	var base: float = a.def.lunge
	# Arme à distance : élan fixe (souvent un léger recul), jamais aimanté vers la cible.
	if not D6Js.truthy(a.targetId) or D6Js.truthy(a.def.get("shot")):
		return base
	var e = null
	for o in game.enemies:
		if o.id == a.targetId:
			e = o
			break
	if e == null or e.dead:
		return base
	var gap: float = sqrt(D6Geo.dist2(p.x, p.y, e.x, e.y)) - p.r - e.r - 6.0
	return maxf(0.0, minf(base * game.tuning.player.lungeStretch, gap))

static func _sweep_hits(game: Dictionary, a: Dictionary) -> void:
	var p: Dictionary = game.player
	var def: Dictionary = a.def
	var arc: float = def.arc * D6Data.DEG
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0 or _has_id(a.hitIds, e.id):
			continue
		if not D6Geo.in_sector(e.x, e.y, p.x, p.y, def.range, a.angle, arc, e.r):
			continue
		a.hitIds.append(e.id)
		var dx: float = e.x - p.x
		var dy: float = e.y - p.y
		var l: float = maxf(1e-6, sqrt(dx * dx + dy * dy))
		# Knockback dans l'axe du coup, légèrement ouvert vers l'extérieur.
		var kx: float = a.dirX * 0.7 + (dx / l) * 0.3
		var ky: float = a.dirY * 0.7 + (dy / l) * 0.3
		var kl: float = maxf(1e-6, sqrt(kx * kx + ky * ky))
		D6Combat.damage_enemy(game, e, {
			"kind": "strike" if a.strike else "melee",
			"amount": def.damage,
			"dirX": kx / kl,
			"dirY": ky / kl,
			"knockback": def.knockback,
			"hitstop": def.hitstop,
			"canCrit": true,
			"shake": D6Js.nz(def.get("shake"), 0.0),
			"stun": D6Js.nz(def.get("stun"), 0.0), # coups lourds (hache, maillet) : étourdissement des ennemis ordinaires
			"finisher": a.finisher,
		})
	# Parade : un coup détruit les projectiles ennemis qu'il balaie.
	var projectiles: Array = game.projectiles
	var j := 0
	while j < projectiles.size():
		var pr: Dictionary = projectiles[j]
		j += 1
		if pr.get("owner") != "enemy" or D6Js.truthy(pr.get("dead")):
			continue
		if D6Geo.in_sector(pr.x, pr.y, p.x, p.y, def.range, a.angle, arc, pr.r):
			pr.dead = true
			game.telemetry.deflects += 1.0
			D6State.emit(game, "deflect", {"x": pr.x, "y": pr.y})

# ---------------------------------------------------------------- dash

static func _start_dash(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning.dash
	var dx: float = p.moveX
	var dy: float = p.moveY
	var l: float = sqrt(dx * dx + dy * dy)
	if l > 0.2:
		dx /= l
		dy /= l
	else:
		dx = D6Trig.cos(p.facing)
		dy = D6Trig.sin(p.facing)
	if p.state == "attack":
		D6State.emit(game, "cancel", {"from": "attack"})
	if p.state == "cast":
		_release_skill(game)
	p.attack = null
	p.dashCharges -= 1.0
	p.dodgedIds.clear() # chaque dash compte ses esquives parfaites, une fois par coup
	p.dashDirX = dx
	p.dashDirY = dy
	p.dashT = t.duration
	p.iframes = maxf(p.iframes, t.iframes)
	p.dodgeIframes = maxf(p.dodgeIframes, t.iframes)
	p.facing = D6Trig.atan2(dy, dx)
	p.state = "dash"
	p.stateTime = 0.0
	game.hitstop = 0.0
	game.telemetry.dashes += 1.0
	D6State.emit(game, "dash", {"x": p.x, "y": p.y, "dirX": dx, "dirY": dy, "charges": p.dashCharges})
	D6Combat.fire_procs(game, "dash") # une charge de dash dépensée (déflagration, éclair… : combat)

static func _update_dash(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var speed: float = (t.dash.distance * D6Js.nz(p.stats.get("dashDistanceMult"), 1.0)) / t.dash.duration
	p.vx = p.dashDirX * speed
	p.vy = p.dashDirY * speed
	p.dashT -= dt
	if p.dashT <= 0.0:
		p.state = "free"
		p.stateTime = 0.0
		p.strikeWindow = t.dash.strikeWindow
		# L'élan se prolonge à la vitesse de course : sortie de dash fluide, pas un arrêt sec.
		var run: float = t.player.speed * p.stats.moveSpeedMult
		p.vx = p.dashDirX * run
		p.vy = p.dashDirY * run
		D6State.emit(game, "dashEnd", {"x": p.x, "y": p.y})

# ---------------------------------------------------------------- compétence (Lance infernale, kits)

static func _start_cast(game: Dictionary, aim_x: float, aim_y: float) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning.skill
	var mx: float = aim_x if D6Js.truthy(aim_x) else p.manualAimX
	var my: float = aim_y if D6Js.truthy(aim_y) else p.manualAimY
	# La Lance voit loin (autoAim.skillRange) ; les autres compétences visent à leur portée.
	var aim: Dictionary = D6Aim.compute_aim(game, mx, my, game.tuning.autoAim.skillRange if s.kind == "lance" else s.get("range"))
	if p.state == "attack":
		D6State.emit(game, "cancel", {"from": "attack"})
	p.attack = null
	p.castDirX = aim.x
	p.castDirY = aim.y
	p.facing = D6Trig.atan2(aim.y, aim.x)
	p.castT = s.castTime
	p.skillCd = s.cooldown * p.stats.skillCooldownMult
	p.state = "cast"
	p.stateTime = 0.0
	D6State.emit(game, "castStart", {"angle": p.facing})
	if s.kind != "lance":
		D6KitSkills.begin_kit_skill(game, s, aim)

static func _update_cast(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	if t.skill.kind == "bond":
		# Bond : l'état 'cast' EST le saut (vitesse imposée, invulnérable) ; il finit à l'atterrissage.
		if D6KitSkills.update_leap(game, dt):
			p.state = "free"
			p.stateTime = 0.0
		return
	var slow: float = t.player.speed * p.stats.moveSpeedMult * t.player.attackMoveMult
	p.vx = p.moveX * slow
	p.vy = p.moveY * slow
	p.castT -= dt
	if p.castT > 0.0:
		return
	_release_skill(game)
	p.state = "free"
	p.stateTime = 0.0

## Effet de la compétence équipée (fin du lancer, ou interruption par un dash / Super).
static func _release_skill(game: Dictionary) -> void:
	if game.tuning.skill.kind == "lance":
		_release_lance(game)
	else:
		D6KitSkills.release_kit_skill(game)

## Tire la Lance préparée. Appelé à la fin du lancer, ou AVANT un dash/Super qui l'interrompt :
## une recharge consommée doit toujours produire une Lance.
static func _release_lance(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning.skill
	D6Projectiles.spawn_projectile(game, {
		"owner": "player",
		"kind": "lance",
		"x": p.x + p.castDirX * (p.r + 4.0),
		"y": p.y + p.castDirY * (p.r + 4.0),
		"vx": p.castDirX * s.speed,
		"vy": p.castDirY * s.speed,
		"r": s.radius,
		"damage": s.damage,
		"range": s.range,
		"pierce": s.pierce,
		"knockback": s.knockback,
		"hitstop": s.hitstop,
	})
	# Recul : la lance repousse légèrement le héros (sensation de puissance).
	p.vx -= p.castDirX * 120.0
	p.vy -= p.castDirY * 120.0
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": D6Trig.atan2(p.castDirY, p.castDirX)})

# ---------------------------------------------------------------- gadget (Nova de cendres, kits)

static func use_gadget(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	var g: Dictionary = game.tuning.gadget
	if p.state == "dead" or p.state == "super" or p.gadgetCharges <= 0.0:
		return false
	if g.kind != "nova":
		return D6KitGadgets.use_kit_gadget(game, g)
	p.gadgetCharges -= 1.0
	p.iframes = maxf(p.iframes, g.iframes)
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var dx: float = e.x - p.x
		var dy: float = e.y - p.y
		var rr: float = g.radius + e.r
		var d2: float = dx * dx + dy * dy
		if d2 >= rr * rr:
			continue
		var l: float = maxf(1e-6, sqrt(d2))
		D6Combat.damage_enemy(game, e, {
			"kind": "gadget", "amount": g.damage, "dirX": dx / l, "dirY": dy / l,
			"knockback": g.knockback, "stun": g.stun, "hitstop": g.hitstop, "canCrit": false,
		})
	D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, g.radius)
	game.telemetry.gadgetUses += 1.0
	D6State.emit(game, "gadget", {"x": p.x, "y": p.y, "r": g.radius, "charges": p.gadgetCharges})
	return true

# ---------------------------------------------------------------- Super (Colère, kits)

static func _start_super(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = game.tuning["super"]
	if p.state == "attack" or p.state == "dash":
		D6State.emit(game, "cancel", {"from": p.state})
	if p.state == "cast":
		_release_skill(game)
	p.attack = null
	p.superCharge = 0.0
	p.superT = s.duration + D6Js.nz(p.stats.get("superDurationBonus"), 0.0)
	p.superTick = 0.0
	if s.kind != "colere":
		D6KitSupers.start_kit_super(game)
	p.state = "super"
	p.stateTime = 0.0
	game.telemetry.superUses += 1.0
	D6State.emit(game, "super", {"x": p.x, "y": p.y, "r": s.get("radius"), "super": s.kind})
	D6Combat.fire_procs(game, "super") # Super lancé (soin, embrasement… : combat)

static func _update_super(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var s: Dictionary = t["super"]
	_locomotion(game, dt, t.player.speed * p.stats.moveSpeedMult * s.speedMult)
	p.superT -= dt
	if s.kind != "colere":
		D6KitSupers.tick_kit_super(game, dt, s)
	else:
		_colere_tick(game, dt, s)
	if p.superT <= 0.0:
		p.state = "free"
		p.stateTime = 0.0
		D6State.emit(game, "superEnd", {"x": p.x, "y": p.y})

## Colère : tourbillon qui frappe tout autour à intervalle fixe et efface les projectiles.
static func _colere_tick(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superTick -= dt
	if p.superTick <= 0.0:
		p.superTick += s.tickInterval
		var enemies: Array = game.enemies
		var i := 0
		while i < enemies.size():
			var e: Dictionary = enemies[i]
			i += 1
			if e.dead or e.spawnT > 0.0:
				continue
			var dx: float = e.x - p.x
			var dy: float = e.y - p.y
			var rr: float = s.radius + e.r
			var d2: float = dx * dx + dy * dy
			if d2 >= rr * rr:
				continue
			var l: float = maxf(1e-6, sqrt(d2))
			D6Combat.damage_enemy(game, e, {
				"kind": "super", "amount": s.damagePerTick, "dirX": dx / l, "dirY": dy / l,
				"knockback": s.knockback, "canCrit": true,
			})
		D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, s.radius)
		D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": s.radius})
