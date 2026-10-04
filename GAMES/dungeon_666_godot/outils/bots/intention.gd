extends RefCounted
## Portage de tools/bots.mjs — INTENTION : ce que le bot veut faire avant de regarder les menaces.
## En combat : choisir une cible, s'en approcher, frapper, lancer les actions des trois
## emplacements (compétences, gadgets) et l'ultime (attaque TENUE quand la jauge est pleine).
## Une intention : {mx, my, attack, slots: [visée {x, y} ou null par emplacement], superP (tenir
## l'attaque pour l'ultime), tap (jauge pleine sans vouloir l'ultime : frapper par appuis brefs)}.
## Hors combat : attendre la vague, ramasser, toucher la récompense, choisir une porte.

const Base = preload("res://outils/bots/base.gd")
const Anticipation = preload("res://outils/bots/anticipation.gd")

const STANDOFF_GAP := 18.0 # u entre les bords du héros et de sa cible
const REACH_MARGIN := 6.0 # u retirées à la portée du coup 1 pour attaquer « sûr »
const PUNISH_BONUS := 220.0 # priorité d'une cible sonnée (u équivalentes)
const ARCHER_BONUS := 50.0
const EXPLODER_BONUS := 40.0
const PYROMANCER_BONUS := 70.0 # une lanceuse de zones fragile : on la presse
const NECROMANCER_BONUS := 140.0 # l'invocateur d'abord : chaque seconde de vie = des diablotins
const CHANNEL_BONUS := 80.0 # en pleine canalisation (alerte violette visible) : le punir l'annule
const BANNER_BONUS := 120.0 # le porte-étendard d'abord : son aura (visible) protège toute la vague
const RECOVER_BONUS := 90.0 # un traqueur ou un porte-pavois qui vient de frapper : fenêtre de punition visible
const GUARD_PENALTY := 150.0 # pavois levé, vu de face : on frappe ailleurs en attendant de le contourner
const FLANK_MARGIN := 0.2 # rad de marge au-delà du bord du pavois avant de frapper
const FLANK_DASH_RANGE := 130.0 # u : assez près pour traverser le porte-pavois d'un dash
const FLANK_DASH_CHARGES := 2.0 # on ne dépense un dash pour contourner que si l'on en garde un pour esquiver
const BUBBLE_PENALTY := 400.0 # bulle d'immunité visible (champion bouclier) : frapper ailleurs en attendant
const AVOID_PENALTY := 500.0 # une brute qui frappe ou un possédé qui gonfle : on s'écarte
const STICKY_BONUS := 35.0 # garder la même cible évite les hésitations
const RETREAT_DIST := 170.0 # u : distance de recul face à une menace de zone
const GADGET_CROWD := 3.0
const GADGET_LOW_HP := 0.35
const GADGET_MIN_GAP := 1.0 # s entre deux gadgets offensifs
const SUPER_CROWD := 2.0
const SUPER_LOW_HP := 0.4
const SUPER_REACH_PAD := 20.0
const SUPER_HOLD_MARGIN := 0.1 # s tenues au-delà de super.holdTime : la décision de lancer l'ultime ne se reprend pas à chaque image
const LANCE_BOSS_WEIGHT := 3.0 # un boss aligné vaut trois ennemis pour la Lance
const SHIELD_PENALTY := 600.0 # u : un Gardien enchaîné (bouclier visible) passe après ses geôliers
# Arme à distance (kits) : on tient la cible à cette distance (u, bord à bord), on recule
# en deçà de RANGED_TOO_CLOSE, et l'on ne tire que si la ligne de tir est dégagée.
const RANGED_KEEP := 210.0
const RANGED_TOO_CLOSE := 120.0

const PICKUP_WINDOW := 5.0 # s passées à ramasser l'or après le combat
const SPAWN_WAIT_DIST := 160.0 # u : on attend la vague à cette distance des cercles d'invocation
const ARRIVE_DIST := 6.0
const LOW_HP_SHOP := 0.6 # achète le soin sous 60 % de PV
const HEAL_DOOR_HP := 0.5
const ELITE_DOOR_HP := 0.75

# Préférences de porte (bonus additif, + un bruit déterministe pour varier les runs).
# Le portail « Ville » (après un Gardien) termine le run : le bot descend toujours (sinon la
# partie passe en mode 'town' et l'épisode de playtest ne progresse plus).
const DOOR_PREFS := {"boon": 3.0, "loot": 2.5, "event": 2.0, "elite": 1.6, "gold": 1.2, "heal": 0.6, "shop": 1.5, "boss": 10.0, "town": -100.0}
const DOOR_NOISE := 1.2
const DOOR_URGENT_HEAL := 4.0 # blessé : la porte de soin passe devant tout
const DOOR_URGENT_SHOP := 2.0
const DOOR_ELITE_RISK := 2.0 # blessé : on évite les élites

# ---------------------------------------------------------------- intention : combat

static func _is_winding_danger(e: Dictionary) -> bool:
	return (e.kind == "brute" and e.state == "windup") or (e.kind == "exploder" and e.get("tele") != null)

## Le héros est-il DEVANT le pavois levé de `e` (ses coups rebondiraient) ? Lu sur ce qui se voit :
## l'orientation du pavois (e.face) et sa largeur dessinée (guardArc), levé ou non (guard_up).
static func _facing_guard(game: Dictionary, e: Dictionary, margin: float = 0.0) -> bool:
	if not D6FoeDefense.guard_up(game, e):
		return false
	var p: Dictionary = game.player
	var def: Dictionary = game.tuning.enemies[e.kind]
	var side := D6Geo.angle_diff(e.face, D6Trig.atan2(p.y - e.y, p.x - e.x))
	return absf(side) <= def.guardArc / 2.0 + margin

static func _target_score(game: Dictionary, mem: Dictionary, p: Dictionary, e: Dictionary) -> float:
	var tele = e.get("tele")
	var score: float = Base.dist_to(p, e) - e.r
	if e.stun > 0.0:
		score -= PUNISH_BONUS
	if e.kind == "archer":
		score -= ARCHER_BONUS
	if e.kind == "exploder" and tele == null:
		score -= EXPLODER_BONUS
	if e.kind == "pyromancer":
		score -= PYROMANCER_BONUS
	if e.kind == "necromancer":
		score -= NECROMANCER_BONUS
	if e.kind == "banner":
		score -= BANNER_BONUS
	if (e.kind == "stalker" or e.kind == "pavois") and e.state == "recover":
		score -= RECOVER_BONUS
	if _facing_guard(game, e):
		score += GUARD_PENALTY
	# Canalisation visible (alerte violette du nécromancien, anneau de l'élite invocateur).
	if (e.kind == "necromancer" and tele != null and D6Js.truthy(tele.get("harmless"))) or e.get("modPhase") == "channel":
		score -= CHANNEL_BONUS
	if Base.num(e, "invuln") > 0.0 and not D6Js.truthy(e.get("boss")):
		score += BUBBLE_PENALTY # bulle d'immunité dessinée
	if _is_winding_danger(e):
		score += AVOID_PENALTY
	if D6Js.truthy(e.get("shielded")):
		score += SHIELD_PENALTY
	if e.id == mem.targetId:
		score -= STICKY_BONUS
	return score

static func _pick_target(game: Dictionary, mem: Dictionary, enemies: Array):
	var p: Dictionary = game.player
	var best = null
	var best_score := INF
	for e in enemies:
		var score := _target_score(game, mem, p, e)
		if score < best_score:
			best_score = score
			best = e
	mem.targetId = best.id if best != null else 0.0
	return best

## Meilleure ligne de tir de la compétence `s` : le plus d'ennemis alignés, tir dégagé.
static func _best_lance_aim(game: Dictionary, enemies: Array, s: Dictionary):
	var p: Dictionary = game.player
	var s_range := Base.num(s, "range")
	var s_radius := Base.num(s, "radius")
	var best = null
	for e in enemies:
		var d := Base.norm(e.x - p.x, e.y - p.y)
		if d.l > s_range:
			continue
		if not Base.clear_shot(game.room, p.x, p.y, e.x, e.y):
			continue
		var count := 0.0
		for o in enemies:
			var ox: float = o.x - p.x
			var oy: float = o.y - p.y
			var along: float = ox * d.x + oy * d.y
			if along < 0.0 or along > s_range:
				continue
			var perp2 := ox * ox + oy * oy - along * along
			var reach: float = s_radius + o.r
			if perp2 < reach * reach:
				count += LANCE_BOSS_WEIGHT if D6Js.truthy(o.get("boss")) else 1.0
		if best == null or count > best.count:
			best = {"x": d.x, "y": d.y, "count": count}
	return best

static func _count_near(p: Dictionary, enemies: Array, radius: float) -> float:
	var n := 0.0
	for e in enemies:
		var reach: float = radius + e.r
		if D6Geo.dist2(p.x, p.y, e.x, e.y) < reach * reach:
			n += 1.0
	return n

static func _boss_near(p: Dictionary, enemies: Array, super_radius: float) -> bool:
	for e in enemies:
		if D6Js.truthy(e.get("boss")) and Base.dist_to(p, e) < super_radius + e.r + SUPER_REACH_PAD:
			return true
	return false

static func _ability_intent(game: Dictionary, mem: Dictionary, enemies: Array, intent: Dictionary, opts: Dictionary) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var hp_frac: float = p.hp / p.maxHp
	_slot_intents(game, mem, enemies, intent, opts, hp_frac)
	var super_radius := Base.num(t["super"], "radius")
	var near_super := _count_near(p, enemies, super_radius + SUPER_REACH_PAD)
	var boss_near := _boss_near(p, enemies, super_radius)
	# Ultime : jauge pleine (le bouton d'attaque le montre), il faut TENIR l'attaque. Une fois
	# décidé, le bot tient le temps du maintien : il ne relâche pas parce qu'un ennemi a reculé.
	if p.superCharge >= 1.0 and (near_super >= SUPER_CROWD or boss_near or (near_super >= 1.0 and hp_frac < SUPER_LOW_HP)):
		mem.superHoldUntil = game.time + t["super"].holdTime + SUPER_HOLD_MARGIN
	intent.superP = p.superCharge >= 1.0 and game.time < mem.get("superHoldUntil", -1.0)
	# Jauge pleine sans vouloir l'ultime : tenir l'attaque le lancerait. Le bot frappe par appuis.
	intent.tap = p.superCharge >= 1.0 and not intent.superP

## Les trois emplacements, lus comme sur leurs boutons (D6Loadout.slot_view : prêt ou non) : une
## compétence prête part sur la meilleure ligne (une seule par image), un gadget prêt sert quand
## la foule presse ou que les PV sont bas (un par GADGET_MIN_GAP, tous emplacements confondus).
static func _slot_intents(game: Dictionary, mem: Dictionary, enemies: Array, intent: Dictionary, opts: Dictionary, hp_frac: float) -> void:
	var p: Dictionary = game.player
	var attack = p.get("attack")
	var can_cast: bool = p.state == "free" or (p.state == "attack" and attack != null and attack.get("phase") == "recovery")
	for i in D6Loadout.SLOTS:
		var view = D6Loadout.slot_view(game, i)
		if view == null or not view.ready:
			continue
		var def: Dictionary = D6Loadout.slot_def(game, i) # son propre héros : portée, rayon
		if view.kind == "skill":
			if not can_cast:
				continue
			var aim = _best_lance_aim(game, enemies, def)
			if aim != null and aim.count >= 1.0:
				intent.slots[i] = aim
				can_cast = false
		elif opts.gadget and game.time - mem.lastGadget > GADGET_MIN_GAP:
			var near := _count_near(p, enemies, Base.num(def, "radius"))
			if near >= GADGET_CROWD or (hp_frac < GADGET_LOW_HP and near >= 1.0):
				intent.slots[i] = {"x": 0.0, "y": 0.0}
				mem.lastGadget = game.time

static func _melee_intent(game: Dictionary, p: Dictionary, target: Dictionary, d: float, intent: Dictionary) -> void:
	var standoff: float = target.r + p.r + STANDOFF_GAP
	var reach: float = game.tuning.combo[0].range + target.r - REACH_MARGIN
	if d > standoff:
		var nav := Base.nav_dir(game.room, p.x, p.y, target.x, target.y, p.r)
		intent.mx = nav.x
		intent.my = nav.y
	intent.attack = d <= reach

static func engage_intent(game: Dictionary, mem: Dictionary, enemies: Array, opts: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var target: Dictionary = _pick_target(game, mem, enemies)
	var intent := {"mx": 0.0, "my": 0.0, "attack": false, "slots": [null, null, null], "superP": false, "tap": false}
	var d := Base.dist_to(p, target)
	# Gardien dissous (il va réapparaître) : on ne court pas après une silhouette, on lit le sol.
	if D6Js.truthy(target.get("hidden")):
		_ability_intent(game, mem, enemies, intent, opts)
		return intent
	var weapon = game.tuning.get("weapon")
	if _facing_guard(game, target, FLANK_MARGIN):
		_flank_intent(game, p, target, d, intent, opts)
	elif _is_winding_danger(target):
		# Recul face à une brute qui arme son coup ou un possédé qui gonfle.
		if d < RETREAT_DIST + target.r:
			var away := Base.norm(p.x - target.x, p.y - target.y)
			intent.mx = away.x
			intent.my = away.y
	elif weapon is Dictionary and weapon.get("kind") == "ranged":
		_ranged_intent(game, p, target, d, intent)
	else:
		_melee_intent(game, p, target, d, intent)
	_ability_intent(game, mem, enemies, intent, opts)
	return intent

## Porte-pavois vu de face : on le contourne au plus près (il pivote moins vite qu'on ne tourne
## autour de lui), sans frapper (les coups rebondiraient). Avec deux charges de dash, on le
## TRAVERSE : le dash passe à travers les ennemis et dépose le héros dans son dos.
static func _flank_intent(game: Dictionary, p: Dictionary, target: Dictionary, d: float, intent: Dictionary, opts: Dictionary) -> void:
	var rx: float = (p.x - target.x) / maxf(1e-6, d)
	var ry: float = (p.y - target.y) / maxf(1e-6, d)
	# Côté où le héros se trouve déjà par rapport à la face du pavois : on continue de ce côté.
	var side := 1.0 if D6Trig.cos(target.face) * ry - D6Trig.sin(target.face) * rx >= 0.0 else -1.0
	var orbit: float = target.r + p.r + STANDOFF_GAP
	var pull := D6Geo.clampv((d - orbit) / orbit, -1.0, 1.0) # trop loin : on se rapproche en tournant
	var dir := Base.norm(-ry * side - rx * pull, rx * side - ry * pull)
	intent.mx = dir.x
	intent.my = dir.y
	intent.attack = false
	if opts.dash and Anticipation.can_dash_now(game) and p.dashCharges >= FLANK_DASH_CHARGES and d < FLANK_DASH_RANGE:
		intent.dash = {"x": -rx, "y": -ry}

## Arme à distance : garder la cible à bonne distance, tirer quand la ligne est dégagée.
static func _ranged_intent(game: Dictionary, p: Dictionary, target: Dictionary, d: float, intent: Dictionary) -> void:
	var gap: float = d - target.r - p.r
	var reach: float = game.tuning.combo[0].range + target.r - REACH_MARGIN
	var shot := Base.clear_shot(game.room, p.x, p.y, target.x, target.y)
	if gap > RANGED_KEEP or not shot:
		var nav := Base.nav_dir(game.room, p.x, p.y, target.x, target.y, p.r)
		intent.mx = nav.x
		intent.my = nav.y
	elif gap < RANGED_TOO_CLOSE:
		var away := Base.norm(p.x - target.x, p.y - target.y)
		intent.mx = away.x
		intent.my = away.y
	intent.attack = shot and d <= reach
	if intent.attack:
		var aim := Base.norm(target.x - p.x, target.y - p.y)
		intent.aimX = aim.x
		intent.aimY = aim.y

# ---------------------------------------------------------------- intention : hors combat

static func nearest(p: Dictionary, list: Array):
	var best = null
	var best_d := INF
	for o in list:
		var d := D6Geo.dist2(p.x, p.y, o.x, o.y)
		if d < best_d:
			best_d = d
			best = o
	return best

static func _door_at(doors: Array, index):
	var i := int(index)
	return doors[i] if i >= 0 and i < doors.size() else null

static func _remember_door(game: Dictionary, mem: Dictionary, index: int):
	mem.doorFloor = game.run.floor
	mem.doorRoom = game.room
	mem.door = index
	return _door_at(game.room.doors, index)

static func _door_score(game: Dictionary, d: Dictionary, i: int, hp_frac: float) -> float:
	var s: float = DOOR_PREFS.get(d.reward, 1.0)
	if d.reward == "heal" and hp_frac < HEAL_DOOR_HP:
		s += DOOR_URGENT_HEAL
	if d.reward == "shop" and hp_frac < LOW_HP_SHOP:
		s += DOOR_URGENT_SHOP
	if d.reward == "elite" and hp_frac < ELITE_DOOR_HP:
		s -= DOOR_ELITE_RISK
	s += (float(Base.mix_hash([game.seed, game.run.floor, i])) / Base.U32) * DOOR_NOISE
	return s

## Porte choisie (mémorisée pour la salle). Le portail de la Ville (après un Gardien) termine le
## run : il n'est JAMAIS pris, sauf demande explicite (mem.wantTown, posé par l'appelant). Rend
## null si aucune porte n'est acceptable (entraînement sans demande : le bot reste dans la salle).
static func _choose_door(game: Dictionary, mem: Dictionary):
	var p: Dictionary = game.player
	var doors: Array = game.room.doors
	if mem.doorFloor == game.run.floor and is_same(mem.get("doorRoom"), game.room):
		return _door_at(doors, mem.door)
	var town := -1
	for i in doors.size():
		if doors[i].reward == "town":
			town = i
			break
	if D6Js.truthy(mem.get("wantTown")) and town >= 0:
		return _remember_door(game, mem, town)
	# Sur demande seulement (mem.wantRewards, posé par l'appelant) : la première porte qui mène à
	# une récompense voulue. Sans cette option, le choix ci-dessous est inchangé.
	var wanted = mem.get("wantRewards")
	if wanted is Array:
		for i in doors.size():
			if wanted.has(doors[i].reward):
				return _remember_door(game, mem, i)
	var hp_frac: float = p.hp / p.maxHp
	var best := -1
	var best_score := -INF
	for i in doors.size():
		var d: Dictionary = doors[i]
		if d.reward == "town":
			continue
		var s := _door_score(game, d, i, hp_frac)
		if s > best_score:
			best_score = s
			best = i
	return _remember_door(game, mem, best)

static func _toward(game: Dictionary, intent: Dictionary, x: float, y: float) -> Dictionary:
	var p: Dictionary = game.player
	if D6Geo.dist2(p.x, p.y, x, y) < ARRIVE_DIST * ARRIVE_DIST:
		intent.mx = 0.0
		intent.my = 0.0
		return intent
	var d := Base.nav_dir(game.room, p.x, p.y, x, y, p.r)
	intent.mx = d.x
	intent.my = d.y
	return intent

static func _any_open(doors: Array) -> bool:
	for d in doors:
		if D6Js.truthy(d.get("open")):
			return true
	return false

## Entre deux vagues, après le combat : ramasser, toucher la récompense, prendre une porte.
static func explore_intent(game: Dictionary, mem: Dictionary) -> Dictionary:
	var room: Dictionary = game.room
	var p: Dictionary = game.player
	var base := {"mx": 0.0, "my": 0.0, "attack": false, "slots": [null, null, null], "superP": false, "tap": false}
	if not D6Js.truthy(room.get("cleared")):
		var s = nearest(p, game.spawns)
		if s == null:
			return _toward(game, base, room.w / 2.0, room.h / 2.0)
		if Base.dist_to(p, s) > SPAWN_WAIT_DIST:
			return _toward(game, base, s.x, s.y)
		return base
	var hurt: bool = p.hp < p.maxHp
	var pickups: Array = game.pickups.filter(func(k): return k.kind == "gold" or hurt)
	if not pickups.is_empty() and game.time - Base.num(room, "clearedAt") < PICKUP_WINDOW:
		var k = nearest(p, pickups)
		return _toward(game, base, k.x, k.y)
	var it = room.get("interact")
	if it != null and not D6Js.truthy(it.get("used")):
		return _toward(game, base, it.x, it.y)
	if not _any_open(room.doors):
		return base
	var door = _choose_door(game, mem)
	if door == null:
		return base
	return _toward(game, base, door.x + door.w / 2.0, door.h / 2.0)
