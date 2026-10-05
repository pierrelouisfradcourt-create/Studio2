class_name D6Player
extends RefCounted
## Portage de src/sim/player.mjs.
## Le héros : machine à états (free | attack | dash | cast | super | dead), tampon d'input,
## annulations (cancels). Règle de feel n°1 : le DASH annule presque tout, tout de suite.
##
## DÉPLACEMENT DE CLASSE (étape 1 bis) : le bouton de dash joue le geste de la classe, réglé par
## tuning.dash (bloc actif, D6Loadout.resolve_kit) et son `kind` : 'dash' (Revenant, l'historique),
## 'saut' (Bourreau : invulnérable en l'air, choc qui repousse à l'atterrissage, aucune annulation
## en vol), 'roulade' (Chasseresse : longue, elle prépare le prochain tir). Les trois passent par
## l'état 'dash' : tout ce qui parle du dash (charges, recharge, i-frames, esquive parfaite, frappe
## de dash, procs) vaut pour les trois. Le geste FRANCHIT le terrain bas (rivière, obstacle bas) et
## finit toujours sur la terre ferme (_plan_move) ; il ne s'annule pas au-dessus de l'eau.
##
## KITS : le code est choisi par le `kind` de l'entrée équipée (kits). Le kit d'origine
## (Lame, Lance, Nova, Colère) est joué ICI, à l'identique ; les autres par kit_* :
##   arme 'ranged'      -> kit_shots.fire_weapon_shots (traits au début de l'actif, pas de balayage)
##   compétence ≠ lance -> kit_skills (chain, bond, brasier, volee)
##   gadget ≠ nova      -> kit_gadgets (bombe, piege, totem)
##   Super ≠ colere     -> kit_supers (ultimes de classe : forme, magie, meute ; réserve : sentence, nuee)
##   compétence `canal` -> un ancien Super (Colère, Sentence, Nuée) joué dans l'état 'super' sur la
##                         recharge de la compétence (player.channel), sans toucher à la jauge d'ultime
##   compétences neuves (étape 4) -> sim/kit_neuves.gd, par les mêmes chemins (état 'cast', charges).
##                         Le Trait de Nemrod se BANDE : son lancer (castTime) est sa charge, il part
##                         seul à la fin ; un SECOND appui sur son bouton le lâche aussitôt
##                         (_press_slot). Aucun champ n'est ajouté à l'entrée d'un pas.
## Les tirs et zones posés par le héros vivent dans la salle (kit_common.kit_store).
##
## COMBAT V3 — trois EMPLACEMENTS d'action (D6Loadout : game.kit.slots, player.slots) : une
## compétence part par le tampon et l'état 'cast', avec SA recharge ; un gadget part tout de suite,
## sur SES charges. L'ULTIME n'a plus de bouton : jauge pleine, l'attaque MAINTENUE l'arme
## (player.superHold) et il part à super.holdTime ; relâcher annule. Pendant l'armement le coup en
## cours se joue, aucun nouveau coup ne part. Seul un appui COMMENCÉ jauge pleine arme
## (player.superArm) : tenir l'attaque depuis avant enchaîne le combo (design/COMBAT_V3.md).
##
## InputFrame attendu (produit par l'entrée, ou par un bot) :
##   { moveX, moveY,            // [-1, 1], norme <= 1 (analogique)
##     aimX, aimY,              // visée manuelle (0, 0 = visée assistée)
##     attack,                  // maintenu : enchaîne le combo ; jauge pleine : arme l'ultime
##     attackPressed, dashPressed,                      // fronts
##     skill1Pressed, skill2Pressed, skill3Pressed,     // fronts des trois emplacements
##     skill1AimX, skill1AimY, … }                      // visée de l'emplacement (0, 0 = assistée)

const Neuves := preload("res://sim/kit_neuves.gd")
const PRIORITY := ["dash", "skill", "attack"]
const SLOT_PRESSED := ["skill1Pressed", "skill2Pressed", "skill3Pressed"]
const SLOT_AIM_X := ["skill1AimX", "skill2AimX", "skill3AimX"]
const SLOT_AIM_Y := ["skill1AimY", "skill2AimY", "skill3AimY"]

## `ids.includes(id)` : comparaison par `==` (Array.has distingue 1 de 1.0, JavaScript non).
static func _has_id(ids: Array, id) -> bool:
	for v in ids:
		if v == id:
			return true
	return false

static func max_dash_charges(game: Dictionary) -> float:
	return game.tuning.dash.charges + game.player.stats.dashChargesBonus

## Sorte du déplacement de classe actif : "dash", "saut" ou "roulade".
static func move_kind(game: Dictionary) -> String:
	return D6Js.nz(game.tuning.dash.get("kind"), D6Loadout.DEFAULT_MOVE)

## Vrai tant que le héros FRANCHIT le terrain bas : déplacement de classe en cours, ou Bond en l'air.
static func crossing(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.state == "dash":
		return true
	var cast = p.get("cast")
	return p.state == "cast" and cast is Dictionary and cast.get("kind") == "bond"

## Vrai si le héros est AU-DESSUS d'une rivière ou d'un obstacle bas (en plein franchissement) :
## rien ne coupe alors son geste — ni frappe, ni second dash, ni ultime. On ne s'arrête pas dans l'eau.
static func _over_low(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	return crossing(game) and D6Physics.low_at(game.room, p.x, p.y, p.r)

## Hauteur du héros en l'air, en cloche (0 au sol, 1 au sommet) : le SAUT du Bourreau. 0 pour un
## dash ou une roulade (au ras du sol). L'affichage dessine le héros d'autant plus haut.
static func air(game: Dictionary) -> float:
	var p: Dictionary = game.player
	if p.state != "dash" or move_kind(game) != "saut" or p.dashDur <= 0.0:
		return 0.0
	return D6Trig.sin(PI * D6Geo.clampv(1.0 - p.dashT / p.dashDur, 0.0, 1.0))

## Où le déplacement de classe POSERAIT le héros s'il partait maintenant dans la direction (dx, dy),
## unitaire : {x, y, time (s de vol), full (false = raccourci : l'arrivée tombait dans l'eau)}.
## Lecture pure (rien ne bouge) : pour un retour de visée, ou un bot qui connaît son héros.
static func move_landing(game: Dictionary, dx: float, dy: float) -> Dictionary:
	var p: Dictionary = game.player
	var speed := _dash_speed(game)
	var moves := 0
	var left: float = game.tuning.dash.duration
	while true:
		left -= D6Data.DT
		if left <= 0.0:
			break
		moves += 1
	var firm := D6Physics.fly_plan(game.room, p, dx * speed * D6Data.DT, dy * speed * D6Data.DT, moves)
	return {"x": D6Physics.fly_end.x, "y": D6Physics.fly_end.y, "time": float(firm) * D6Data.DT, "full": firm == moves}

## Ce que l'affichage lit du DÉPLACEMENT DE CLASSE (bouton, pictogramme), sans connaître l'intérieur :
##   id, kind, name, icon, text : le déplacement de la classe (data/classes.json, `moves`)
##   charges, maxCharges        : charges prêtes (entières) et maximum
##   ready                      : une charge au moins
##   rechargeFrac               : part de la recharge de la prochaine charge déjà faite (1 = toutes pleines)
##   active                     : le geste est en cours ; air : hauteur du saut (0..1)
static func move_view(game: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var id := D6Loadout.move_id(game)
	var moves = t.get("moves")
	var def = moves.get(id) if moves is Dictionary else null
	var kind := move_kind(game)
	var max_c := max_dash_charges(game)
	var need: float = t.dash.recharge * p.stats.dashRechargeMult
	return {
		"id": id, "kind": kind,
		"name": def.name if def is Dictionary else "Dash", "icon": D6Js.nz(def.get("icon"), kind) if def is Dictionary else kind,
		"text": D6Js.nz(def.get("text"), "") if def is Dictionary else "",
		"charges": floorf(p.dashCharges), "maxCharges": max_c, "ready": p.dashCharges >= 1.0,
		"rechargeFrac": 1.0 if p.dashCharges >= max_c or need <= 0.0 else D6Geo.clampv(p.dashRecharge / need, 0.0, 1.0),
		"active": p.state == "dash", "air": air(game),
	}

static func _buffer_action(p: Dictionary, action: String, t: float, aim_x: float = 0.0, aim_y: float = 0.0, slot: int = 0) -> void:
	var cur = p.buffer.action
	# Un dash en attente n'est jamais écrasé par une action moins prioritaire.
	if D6Js.truthy(cur) and p.buffer.t > 0.0 and PRIORITY.find(cur) < PRIORITY.find(action):
		return
	p.buffer.action = action
	p.buffer.t = t
	p.buffer.aimX = aim_x
	p.buffer.aimY = aim_y
	p.buffer.slot = float(slot) # emplacement de la compétence en attente

## Vrai si un dash peut partir maintenant (utilisé aussi pour annuler le gel d'impact).
static func can_dash(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.dashCharges < 1.0:
		return false
	if p.state == "free" or p.state == "attack":
		return true
	if p.state == "cast":
		return not _over_low(game) # un Bond ne se coupe pas au-dessus d'une rivière
	if p.state == "dash":
		# re-dash quand il reste moins de cette part du dash — jamais au-dessus de l'eau
		return p.dashT <= game.tuning.dash.duration * game.tuning.dash.chainFrom and not _over_low(game)
	return false

static func _can_attack(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.state == "free":
		return true
	# Frappe de dash : attaquer en fin de dash coupe la ruée et frappe tout de suite.
	if p.state == "dash":
		return p.dashT <= game.tuning.dash.duration * game.tuning.dash.strikeCancelFrom and not _over_low(game)
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

static func _can_skill(p: Dictionary, slot: int) -> bool:
	if p.slots[slot].cd > 0.0:
		return false
	if p.state == "free":
		return true
	return p.state == "attack" and p.attack.phase == "recovery"

static func _can_super(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	if p.superCharge < 1.0 or _over_low(game) or D6KitSupers.acting(game):
		return false # jauge pleine, terre ferme, et jamais deux ultimes à la fois
	return p.state == "free" or p.state == "attack" or p.state == "cast" or p.state == "dash"

## Une action ne mérite le tampon que si elle peut partir pendant sa fenêtre : marteler un dash
## sans charge, ou une compétence en recharge, ne doit JAMAIS avaler la frappe qui suit.
static func _feasible_soon(game: Dictionary, action: String, window: float, slot: int = 0) -> bool:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	if action == "dash":
		if p.dashCharges >= 1.0:
			return true
		return t.dash.recharge * p.stats.dashRechargeMult - p.dashRecharge <= window
	if action == "skill":
		return p.slots[slot].cd <= window
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
	var held: bool = D6Js.truthy(input.get("attack"))
	# L'ultime ne s'arme que si l'APPUI A COMMENCÉ jauge pleine : un appui tenu depuis avant ne
	# l'arme jamais, il faut relâcher et rappuyer.
	if held and not p.attackHeld:
		p.superArm = p.superCharge >= 1.0 and not D6KitSupers.acting(game)
	p.attackHeld = held
	if not held:
		p.superHold = 0.0 # relâcher l'attaque annule l'armement de l'ultime
		p.superArm = false
	if D6Js.truthy(input.get("attackPressed")):
		_buffer_action(p, "attack", lock_buf)
	for i in D6Loadout.SLOTS:
		if D6Js.truthy(input.get(SLOT_PRESSED[i])):
			_press_slot(game, i, _num(input, SLOT_AIM_X[i]), _num(input, SLOT_AIM_Y[i]), lock_buf)
	if D6Js.truthy(input.get("dashPressed")) and _feasible_soon(game, "dash", buf):
		_buffer_action(p, "dash", buf)
	return p.buffer.action == "dash" and p.buffer.t > 0.0

## Bouton d'un emplacement : une compétence attend dans le tampon (la fin d'un coup engagé), un
## gadget part tout de suite, un emplacement vide ne fait rien.
static func _press_slot(game: Dictionary, slot: int, aim_x: float, aim_y: float, window: float) -> void:
	match D6Loadout.slot_kind(game, slot):
		"skill":
			if Neuves.second_press(game, slot):
				return # le Trait qui se bande sur ce bouton est lâché
			if _feasible_soon(game, "skill", window, slot):
				_buffer_action(game.player, "skill", window, aim_x, aim_y, slot)
		"gadget":
			use_gadget(game, slot, aim_x, aim_y)

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
	# Attaque maintenue : enchaîne le combo sans re-taper (confort mobile). Pendant l'armement de
	# l'ultime (superHold > 0), aucun NOUVEAU coup ne part : celui qui est en cours se joue.
	if p.attackHeld and not D6Js.truthy(p.buffer.action) and _can_attack(game) and p.state != "dash" and p.superHold <= 0.0:
		_start_attack(game)
	_tick_super_hold(game, dt)
	_update_state(game, dt)
	# Le déplacement de classe et le Bond franchissent le terrain bas ; la marche s'y arrête.
	D6Physics.move_circle(game.room, p, p.vx * dt, p.vy * dt, crossing(game))

## Ultime par MAINTIEN : un appui COMMENCÉ jauge pleine (player.superArm, posé par read_input) et
## tenu sans interruption fait monter superHold (plafonné à super.holdTime) ; arrivé là, l'ultime
## part dès qu'il le peut (_can_super), en coupant ce qui reste du coup comme le faisait son
## bouton. Un appui commencé avant que la jauge soit pleine n'arme rien : il enchaîne le combo.
static func _tick_super_hold(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	if not p.attackHeld or not p.superArm or p.superCharge < 1.0 or p.state == "super":
		p.superHold = 0.0
		return
	var need: float = game.tuning["super"].holdTime
	p.superHold = minf(need, p.superHold + dt)
	if p.superHold >= need and _can_super(game):
		_start_super(game)

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
	for st in p.slots:
		st.cd = maxf(0.0, st.cd - dt)
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
		"skill":
			var slot := int(p.buffer.slot)
			if _can_skill(p, slot):
				var ax: float = p.buffer.aimX
				var ay: float = p.buffer.aimY
				p.buffer.action = null
				_start_cast(game, slot, ax, ay)
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
		Neuves.on_swing(game, a) # Ombre jumelle (étape 5) : elle répète le coup de sa place
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
	p.dashDur = t.duration
	_plan_move(game)
	p.iframes = maxf(p.iframes, t.iframes)
	p.dodgeIframes = maxf(p.dodgeIframes, t.iframes)
	p.facing = D6Trig.atan2(dy, dx)
	p.state = "dash"
	p.stateTime = 0.0
	game.hitstop = 0.0
	game.telemetry.dashes += 1.0
	D6State.emit(game, "dash", {"x": p.x, "y": p.y, "dirX": dx, "dirY": dy, "charges": p.dashCharges, "move": move_kind(game)})
	D6Combat.fire_procs(game, "dash") # une charge de dash dépensée (déflagration, éclair… : combat)

## Vitesse du déplacement de classe : sa distance (× la statistique de classe) sur sa durée.
static func _dash_speed(game: Dictionary) -> float:
	var t: Dictionary = game.tuning.dash
	return (t.distance * D6Js.nz(game.player.stats.get("dashDistanceMult"), 1.0)) / t.duration

## Le déplacement FRANCHIT le terrain bas et doit finir sur la terre ferme. On compte d'avance ses
## pas de vol (ceux de _update_dash : un déplacement tant que dashT reste > 0 après décompte) ; si
## l'arrivée tombait dans une rivière ou sur un obstacle bas, le geste est RACCOURCI au dernier pas
## sur la terre ferme — au pire sur place : la charge est dépensée, l'esquive gardée, jamais de chute.
static func _plan_move(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var speed := _dash_speed(game)
	var moves := 0
	var left: float = p.dashT
	while true:
		left -= D6Data.DT
		if left <= 0.0:
			break
		moves += 1
	var vx: float = p.dashDirX * speed
	var vy: float = p.dashDirY * speed
	var firm := D6KitCommon.flight_moves(game, vx, vy, moves)
	if firm < moves:
		p.dashT = (float(firm) + 0.5) * D6Data.DT
		p.dashDur = p.dashT
		D6KitCommon.flight_cut(game, vx, vy, moves, firm, move_kind(game))

static func _update_dash(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var speed := _dash_speed(game)
	p.vx = p.dashDirX * speed
	p.vy = p.dashDirY * speed
	p.dashT -= dt
	if p.dashT <= 0.0:
		p.state = "free"
		p.stateTime = 0.0
		p.strikeWindow = t.dash.strikeWindow
		if move_kind(game) == "saut":
			_land_jump(game)
		else:
			# L'élan se prolonge à la vitesse de course : sortie de dash fluide, pas un arrêt sec.
			var run: float = t.player.speed * p.stats.moveSpeedMult
			p.vx = p.dashDirX * run
			p.vy = p.dashDirY * run
		D6State.emit(game, "dashEnd", {"x": p.x, "y": p.y})

## Ce sur quoi le saut RETOMBE est chassé DEVANT lui (dans le sens du saut), au contact : le
## Bourreau garde face à lui ce qu'il écrase, sa frappe d'atterrissage porte. Le corps déplacé
## reste sur la terre ferme et hors des murs (collision de marche).
static func _shove_ahead(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var enemies: Array = game.enemies
	var i := 0
	while i < enemies.size():
		var e: Dictionary = enemies[i]
		i += 1
		if e.dead or e.spawnT > 0.0:
			continue
		var rr: float = p.r + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) >= rr * rr:
			continue
		e.x = p.x + p.dashDirX * rr
		e.y = p.y + p.dashDirY * rr
		D6Physics.move_circle(game.room, e, 0.0, 0.0)

## Atterrissage du SAUT (Bourreau) : il se pose net, et le choc REPOUSSE ce qui l'entoure, sans
## dégât (ce n'est pas une attaque : ni jauge, ni proc « au toucher »). Le Bond, lui, frappe.
static func _land_jump(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var m: Dictionary = game.tuning.dash
	p.vx = 0.0
	p.vy = 0.0
	_shove_ahead(game)
	var pushed := D6KitCommon.push_circle(game, p.x, p.y, m.shockRadius, m.shockKnockback, D6Js.nz(m.get("shockStun"), 0.0))
	D6State.emit(game, "moveLand", {"x": p.x, "y": p.y, "r": m.shockRadius, "move": "saut", "pushed": pushed})

# ---------------------------------------------------------------- compétence (Lance infernale, kits)

## Lance la compétence de l'emplacement `slot` : sa recharge part, l'état 'cast' la retient
## (player.castSlot) jusqu'à son effet.
static func _start_cast(game: Dictionary, slot: int, aim_x: float, aim_y: float) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = D6Loadout.slot_def(game, slot)
	if s.kind == "canal":
		_start_channel(game, slot, s)
		return
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
	p.castSlot = float(slot)
	p.castT = s.castTime
	p.slots[slot].cd = s.cooldown * p.stats.skillCooldownMult
	p.state = "cast"
	p.stateTime = 0.0
	D6State.emit(game, "castStart", {"angle": p.facing, "slot": p.castSlot})
	if s.kind != "lance":
		D6KitSkills.begin_kit_skill(game, s, aim)
		p.cast.manX = mx # visée manuelle du lancer (0, 0 = assistée) : le Trait revise au moment de partir
		p.cast.manY = my

## Compétence `canal` : elle joue un ancien Super (Colère, Sentence, Nuée) dans l'état 'super' —
## invulnérable, dégâts de source « super » — sur SA recharge. La jauge d'ultime n'est ni dépensée
## ni remplie pendant le geste ; les réglages joués sont ceux de player.channel.
static func _start_channel(game: Dictionary, slot: int, s: Dictionary) -> void:
	var p: Dictionary = game.player
	if p.state == "attack":
		D6State.emit(game, "cancel", {"from": "attack"})
	p.attack = null
	p.slots[slot].cd = s.cooldown * p.stats.skillCooldownMult
	p.channel = D6KitSkills.channel_def(game, s)
	p.superT = p.channel.duration
	p.superTick = 0.0
	D6KitSupers.reset_clock(game)
	p.castSlot = float(slot)
	p.state = "super"
	p.stateTime = 0.0
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "castStart", {"angle": p.facing, "slot": p.castSlot})
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": p.facing, "skill": "canal", "super": p.channel.kind, "r": p.channel.get("radius"), "slot": p.castSlot})

static func _update_cast(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	if D6Loadout.cast_def(game).kind == "bond":
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

## Effet de la compétence en cours (fin du lancer, ou interruption par un dash / Super).
static func _release_skill(game: Dictionary) -> void:
	if D6Loadout.cast_def(game).kind == "lance":
		_release_lance(game)
	else:
		D6KitSkills.release_kit_skill(game)

## Tire la Lance préparée. Appelé à la fin du lancer, ou AVANT un dash/Super qui l'interrompt :
## une recharge consommée doit toujours produire une Lance.
static func _release_lance(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var s: Dictionary = D6Loadout.cast_def(game)
	var shot: Dictionary = D6Projectiles.spawn_projectile(game, {
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
	if s.get("blastRadius") != null: # amélioration « Explose à l'impact » (D6Projectiles)
		shot.blastRadius = s.blastRadius
		shot.blastDamage = s.blastDamage
	# Recul : la lance repousse légèrement le héros (sensation de puissance).
	p.vx -= p.castDirX * 120.0
	p.vy -= p.castDirY * 120.0
	game.telemetry.skillCasts += 1.0
	D6State.emit(game, "skill", {"x": p.x, "y": p.y, "angle": D6Trig.atan2(p.castDirY, p.castDirX), "slot": p.castSlot})

# ---------------------------------------------------------------- gadget (Nova de cendres, kits)

## Utilise le gadget de l'emplacement `slot` (une charge). (aim_x, aim_y) : visée de son bouton,
## pour un gadget lancé. Rend false si rien n'est parti (pas un gadget, plus de charge, mort, Super).
static func use_gadget(game: Dictionary, slot: int, aim_x: float = 0.0, aim_y: float = 0.0) -> bool:
	var p: Dictionary = game.player
	if D6Loadout.slot_kind(game, slot) != "gadget":
		return false
	var g: Dictionary = D6Loadout.slot_def(game, slot)
	var st: Dictionary = p.slots[slot]
	if p.state == "dead" or p.state == "super" or st.charges <= 0.0:
		return false
	if g.kind != "nova":
		return D6KitGadgets.use_kit_gadget(game, g, slot, aim_x, aim_y)
	st.charges -= 1.0
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
		D6KitGadgets.draw_in(game, e, g) # amélioration « Aspiration » : attire au lieu de repousser
	D6KitGadgets.nova_fire(game, g) # amélioration « Sol en feu »
	D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, g.radius)
	game.telemetry.gadgetUses += 1.0
	D6State.emit(game, "gadget", {"x": p.x, "y": p.y, "r": g.radius, "charges": st.charges, "slot": float(slot)})
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
	p.superHold = 0.0
	p.superArm = false # l'appui qui vient de lancer l'ultime n'en arme pas un second
	p.channel = null
	p.superT = s.duration + D6Js.nz(p.stats.get("superDurationBonus"), 0.0)
	p.superTick = 0.0
	if s.kind != "colere":
		D6KitSupers.start_kit_super(game) # forme : kit de forme branché ; meute : les limiers apparaissent
	p.state = "super"
	p.stateTime = 0.0
	game.telemetry.superUses += 1.0
	D6State.emit(game, "super", {"x": p.x, "y": p.y, "r": s.get("radius"), "super": s.kind})
	D6Combat.fire_procs(game, "super") # Super lancé (soin, embrasement… : combat)

static func _update_super(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var s: Dictionary = super_def(game)
	_locomotion(game, dt, t.player.speed * p.stats.moveSpeedMult * s.speedMult)
	p.superT -= dt
	if s.kind != "colere":
		D6KitSupers.tick_kit_super(game, dt, s)
	else:
		_colere_tick(game, dt, s)
	if p.superT <= 0.0:
		p.state = "free"
		p.stateTime = 0.0
		p.channel = null
		D6State.emit(game, "superEnd", {"x": p.x, "y": p.y})

## Les réglages du Super EN COURS : ceux de la compétence `canal` qui le joue, sinon l'ultime de la classe.
static func super_def(game: Dictionary) -> Dictionary:
	var ch = game.player.get("channel")
	return ch if ch is Dictionary and game.player.state == "super" else game.tuning["super"]

## Ce que l'affichage lit de l'ULTIME de la classe (jauge, maintien, sorte, minuterie), sans
## connaître l'intérieur : {id, kind ("forme" | "magie" | "invocation"), name, icon, text, charge,
## ready, holdFrac, active, timeFrac, timeLeft, allies}. Détail : D6KitSupers.view.
static func ultimate_view(game: Dictionary) -> Dictionary:
	return D6KitSupers.view(game)

## Colère : tourbillon qui frappe tout autour à intervalle fixe et efface les projectiles.
static func _colere_tick(game: Dictionary, dt: float, s: Dictionary) -> void:
	var p: Dictionary = game.player
	p.superTick -= dt
	if p.superTick <= 0.0:
		p.superTick += s.tickInterval
		var hits := 0.0
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
			hits += 1.0
			D6KitGadgets.draw_in(game, e, s) # amélioration « Œil du cyclone » : aspire
		if hits > 0.0 and s.get("healPerHit") != null:
			D6Combat.heal_scaled(game, hits * s.healPerHit, true) # amélioration « Soif » : à l'échelle de l'étage
		D6Projectiles.destroy_enemy_projectiles_in_circle(game, p.x, p.y, s.radius)
		D6State.emit(game, "superTick", {"x": p.x, "y": p.y, "r": s.radius})
