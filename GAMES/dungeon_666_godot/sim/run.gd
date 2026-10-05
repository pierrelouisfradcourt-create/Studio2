class_name D6Run
extends RefCounted
## Portage de src/sim/run.mjs.
## Le run : descente étage par étage, portes à récompense, choix (bénédiction, butin,
## marchand, autel), Gardiens, checkpoints et téléportation, mort et reprise.
##
## PERMANENT vs TEMPORAIRE (demande de Pierre, V2) :
##   - TEMPORAIRE (game.run) : bénédictions — bonus, pouvoirs, améliorations, synergies. La mort
##     les remet TOUJOURS à zéro : aucun instantané de build n'est figé au Gardien.
##   - PERMANENT (game.meta = profil) : classe, armes, équipement (tout objet trouvé est équipé
##     ou rangé au coffre, jamais perdu), compétences, déblocages de la Ville, Âmes, checkpoints.
##   - La bourse (or) suit le héros, mais Charon en prélève une part à chaque mort.
##   - Mort : retour au DERNIER checkpoint (ou en Ville), le temporaire repart de zéro.
##   - Gardien vaincu (tous les 18 étages) : checkpoint + point de téléportation ; deux portes,
##     « section suivante » (le run continue, build conservé) ou « Ville » (fin du run).
##
## REWARD_LABELS et EVENTS se lisent dans D6Data.tables().run.

const Arbre = preload("res://sim/tree.gd")
const Neuves = preload("res://sim/kit_neuves.gd")
const DOOR_GUARD := 20.0 # garde-fou du tirage de la seconde porte
const MIN_HP := 1.0 # un paiement en PV n'est jamais mortel : il laisse au moins ceci

static func create_run(start_floor) -> Dictionary:
	return {
		"floor": start_floor,
		"gold": 0.0,
		"boons": [],
		"items": {"arme": null, "armure": null, "talisman": null}, # = équipement du PROFIL (game)
		"roomsThisRun": 0.0,
		"streak": 0.0, # salles nettoyées d'affilée sans blessure (procs « streakBonus ») : un coup reçu la remet à zéro
		"startedAt": 0.0,
		"deathRecap": null, # ce que la dernière mort a pris (bénédictions, or) : écran de mort
	}

## La bourse du run est celle du profil : on la recopie à chaque moment clé.
static func sync_purse(game: Dictionary) -> void:
	game.meta.gold = game.run.gold

## Plan de la salle d'un étage : l'entrée du PLAN DE SECTION (sections : rythme, vagues,
## budget, dispositions, bestiaire du Cercle, Gardien) composée avec la porte choisie.
static func plan_for(game: Dictionary, info: Dictionary, door):
	return D6Sections.compose_floor(game.tuning, game.seed, info.floor, door)

static func enter_floor(game: Dictionary, floor_num, door) -> void:
	var t: Dictionary = game.tuning
	var info: Dictionary = D6Floors.floor_info(t, floor_num)
	var plan: Dictionary = plan_for(game, info, door)
	game.run.floor = info.floor
	game.meta.bestFloor = maxf(game.meta.bestFloor, info.floor)
	sync_purse(game)
	D6KitSupers.reset(game, "etage") # un ultime ne suit pas le héros : forme finie, limiers retirés
	Neuves.reset(game) # ni sillage, ni garde, ni parade d'une salle à l'autre
	game.enemies.clear()
	game.projectiles.clear()
	game.hazards.clear()
	game.pickups.clear()
	game.spawns.clear()
	game.room = D6Room.build_room(game, info, plan)
	game.room.plan = plan
	game.info = info
	_place_player(game, info)
	game.run.roomsThisRun += 1.0
	D6State.emit(game, "floorEnter", {"floor": info.floor, "circle": info.circle, "circleName": info.circleName, "section": info.section, "indexInSection": info.indexInSection, "kind": plan.kind, "reward": plan.get("reward"), "pace": plan.get("pace"), "isBoss": info.isBoss})
	# Arène d'essai : les vagues sans fin suivent le plan d'un étage de début de section.
	if game.sandbox:
		game.room.refill = D6Sections.compose_floor(t, game.seed, t.section.sandbox.floor, {"reward": "boon"})

	if plan.kind == "boss":
		var guardian = plan.get("guardian")
		if guardian == null:
			guardian = D6Floors.guardian_for(t, info.section)
		D6Room.spawn_boss(game, guardian)
	elif plan.kind == "combat" or plan.kind == "elite":
		D6Room.launch_next_wave(game)
	else:
		_enter_calm_room(game, plan)

## Le héros à l'entrée de la salle : position, état, charges de gadget de la section.
static func _place_player(game: Dictionary, info: Dictionary) -> void:
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var start: Dictionary = D6Room.player_start(game.room)
	p.x = start.x
	p.y = start.y
	p.vx = 0.0
	p.vy = 0.0
	p.attack = null
	p.state = "free"
	p.facing = -PI / 2.0
	p.buffer.action = null
	# Gadget : charges rendues toutes les `gadgetRefillEvery` étages de la section.
	var every: float = D6Js.nz(t.section.get("gadgetRefillEvery"), t.floors.sectionLength)
	if fmod(info.indexInSection - 1.0, every) == 0.0:
		D6Loadout.refill_gadgets(game)

## Salle calme : l'objet d'interaction est là d'emblée, les portes aussi.
static func _enter_calm_room(game: Dictionary, plan: Dictionary) -> void:
	game.room.cleared = true
	var spot: Dictionary = D6Room.reward_spot(game.room)
	game.room.interact = {"kind": plan.kind, "x": spot.x, "y": spot.y, "r": game.tuning.room.calmRadius, "used": false}
	if plan.kind == "shop":
		game.room.interact.offers = _roll_shop(game)
	if plan.kind == "event":
		game.room.interact.event = D6Rng.pick(game.rng.gen, D6Data.tables().run.EVENTS).id
	if D6Data.tables().calm_rooms.CALM_KINDS.has(plan.kind):
		D6CalmRooms.setup_calm_room(game, game.room.interact)
	_prepare_doors(game, true)

## Fin de combat : récompense, checkpoint, portes.
static func on_room_clear(game: Dictionary) -> void:
	var room: Dictionary = game.room
	var t: Dictionary = game.tuning
	room.cleared = true
	room.clearedAt = game.time
	if room.kind != "boss":
		D6Combat.force_hitstop(game, t.killHitstop.lastEnemy)
	game.telemetry.roomsCleared += 1.0
	game.telemetry.roomTimes.append({"floor": game.run.floor, "kind": room.kind, "time": game.time - room.enteredAt})
	D6State.emit(game, "roomClear", {"floor": game.run.floor, "kind": room.kind, "boss": room.kind == "boss"})
	# Salle nettoyée sans une blessure : la série s'allonge, les procs « roomClear » se déclenchent.
	var untouched: bool = not D6Js.truthy(room.get("hurt"))
	if untouched:
		game.run.streak = D6Js.nz(game.run.get("streak"), 0.0) + 1.0
	D6Combat.fire_procs(game, "roomClear", null, {"untouched": untouched})
	_cancel_enemy_attacks(game)
	var spot: Dictionary = D6Room.reward_spot(room)

	if room.kind == "boss" and game.practice:
		_clear_practice(game)
		return
	if room.kind == "boss":
		_clear_boss(game, spot.x, spot.y)
		return
	_clear_reward(game, spot.x, spot.y)
	_prepare_doors(game, room.get("interact") == null)

## Salle nettoyée : plus aucun coup ennemi ne part (souffle d'un élite ardent, flèche en vol).
static func _cancel_enemy_attacks(game: Dictionary) -> void:
	var hazards: Array = game.hazards
	var i := 0
	while i < hazards.size():
		var h = hazards[i]
		i += 1
		# les flaques s'éteignent d'elles-mêmes
		if D6Js.truthy(h.get("done")) or not D6Js.truthy(h.get("hitsPlayer")) or D6Js.truthy(h.get("burning")):
			continue
		h.done = true
		D6State.emit(game, "hazardCancel", {"id": h.get("id"), "x": h.get("x"), "y": h.get("y")})
	for pr in game.projectiles:
		if pr.get("owner") == "enemy":
			pr.dead = true

## Entraînement : aucune récompense ; une seule porte, retour en Ville.
static func _clear_practice(game: Dictionary) -> void:
	D6Combat.heal_player(game, game.player.maxHp * game.tuning.guardians.clearHeal, true)
	D6State.emit(game, "checkpoint", {"floor": game.run.floor, "practice": true})
	D6Room.make_doors(game, [{"reward": "town"}])
	D6State.emit(game, "doorsOpen", {"count": 1.0})

## Gardien vaincu : checkpoint + point de téléportation (PERMANENTS), Âmes, soin.
## Le build TEMPORAIRE n'est PAS figé : il ne survivra pas à la prochaine mort.
static func _clear_boss(game: Dictionary, cx: float, cy: float) -> void:
	var room: Dictionary = game.room
	var t: Dictionary = game.tuning
	var cp = D6Floors.checkpoint_after_boss(t, game.run.floor)
	var meta: Dictionary = game.meta
	# Le Gardien final n'ouvre aucun checkpoint : il n'y a pas d'étage suivant, et un point de
	# reprise SUR le Gardien du 666 offrait une victoire (et ses Âmes) à chaque reprise.
	if not D6Js.truthy(game.info.isFinal) and not _has_num(meta.checkpoints, cp):
		meta.checkpoints.append(cp)
	meta.checkpoints.sort_custom(func(a, b): return a < b)
	var kind = D6Floors.guardian_for(t, game.info.section)
	meta.guardians[kind] = D6Js.nz(meta.guardians.get(kind), 0.0) + 1.0
	meta.stats.guardianKills += 1.0
	var souls: float = t.progression.souls.guardian + t.progression.souls.guardianPerSection * (game.info.section - 1.0)
	if not game.sandbox:
		meta.souls += souls
		game.telemetry.soulsEarned += souls
		Arbre.gain(game, "guardian") # expérience de classe, et un point la première fois avec cette classe
		Arbre.guardian_down(game, kind)
	D6Combat.heal_player(game, game.player.maxHp * game.tuning.guardians.clearHeal, true)
	sync_purse(game)
	D6State.emit(game, "checkpoint", {"floor": cp, "guardian": kind, "souls": souls})
	if D6Js.truthy(game.info.isFinal):
		game.mode = "victory"
		D6State.emit(game, "victory", {"floor": game.run.floor})
		return
	var rar := "legendaire" if D6Rng.rand(game.rng.gen) < t.loot.bossLegendaryChance else "rare"
	room.interact = {"kind": "loot", "x": cx, "y": cy, "r": t.room.rewardRadius, "used": false, "item": D6Loot.generate_item(game, {"rarity": rar})}
	_prepare_doors(game, true)

## Récompense de fin de salle de combat, selon le plan (porte choisie).
static func _clear_reward(game: Dictionary, cx: float, cy: float) -> void:
	var room: Dictionary = game.room
	var t: Dictionary = game.tuning
	var p: Dictionary = game.player
	var plan: Dictionary = room.plan
	match plan.get("reward"):
		"boon":
			var family = plan.get("family")
			if family == null:
				family = D6Boons.random_family(game)
			room.interact = {"kind": "boon", "x": cx, "y": cy, "r": t.room.rewardRadius, "used": false, "family": family}
		"loot":
			var bonus: float = t.loot.eliteRarityBonus if D6Js.truthy(plan.get("elite")) else 1.0
			room.interact = {"kind": "loot", "x": cx, "y": cy, "r": t.room.rewardRadius, "used": false, "item": D6Loot.generate_item(game, {"rarity": D6Loot.roll_rarity(game, bonus)})}
		"gold":
			var total: float = D6Js.jround(D6Room.random_gold(game) * t.economy.goldReward.mult * p.stats.goldFindMult)
			var n: float = t.economy.goldReward.pickups
			for i in range(int(n)):
				D6Combat.spawn_pickup(game, "gold", cx, cy, maxf(1.0, D6Js.jround(total / n)))
		"heal":
			D6Combat.spawn_pickup(game, "heal", cx, cy, D6Js.jround(p.maxHp * t.economy.healReward))

## Portes de sortie, composées par le PLAN DE SECTION (sections) de l'étage suivant : portes
## imposées (Gardien au 18e, halte, antichambre), sinon deux récompenses tirées selon les poids
## du Cercle, avec la récompense garantie de l'index (épreuve d'élite, chambre forte). Après un
## Gardien : « section suivante » ou « Ville » (téléportation, fin du run).
static func _prepare_doors(game: Dictionary, open_now: bool) -> void:
	var t: Dictionary = game.tuning
	var next: Dictionary = D6Sections.floor_slot(t, game.seed, game.run.floor + 1.0)
	var rewards: Array = []
	if next.get("doors") != null:
		for reward in next.doors:
			rewards.append({"reward": reward})
	else:
		var weights: Array = next.doorWeights
		var weight_of := func(d): return d.weight
		var first = D6Rng.weighted_pick(game.rng.gen, weights, weight_of).reward
		var second = first
		var guard := 0.0
		while second == first:
			var more := guard < DOOR_GUARD
			guard += 1.0
			if not more:
				break
			second = D6Rng.weighted_pick(game.rng.gen, weights, weight_of).reward
		if second == first:
			second = _other_reward(weights, first)
		rewards = [{"reward": first}, {"reward": second}]
		var guarantee = next.get("guarantee")
		if D6Js.truthy(guarantee) and first != guarantee and second != guarantee:
			rewards[1] = {"reward": guarantee}
	if game.room.kind == "boss" and not game.sandbox:
		rewards = [rewards[0], {"reward": "town"}]
	for r in rewards:
		if r.reward == "boon":
			r.family = D6Boons.random_family(game)
	D6Room.make_doors(game, rewards)
	for d in game.room.doors:
		d.open = open_now
	if open_now:
		D6State.emit(game, "doorsOpen", {"count": float(game.room.doors.size())})

## Repli du tirage des portes (garde-fou atteint) : la première récompense POSSIBLE (poids > 0)
## autre que `first`, dans l'ordre des poids ; `first` s'il n'y en a pas d'autre. Aucun tirage.
static func _other_reward(weights: Array, first):
	for d in weights:
		if d.weight > 0.0 and d.reward != first:
			return d.reward
	return first

static func _open_doors(game: Dictionary) -> void:
	var all_open := true
	for d in game.room.doors:
		if not D6Js.truthy(d.get("open")):
			all_open = false
			break
	if all_open:
		return
	for d in game.room.doors:
		d.open = true
	D6State.emit(game, "doorsOpen", {"count": float(game.room.doors.size())})

# ---------------------------------------------------------------- choix (menus)

## Ouvre le menu de l'objet d'interaction touché. La simulation se met en pause.
static func open_interact(game: Dictionary) -> void:
	var it = game.room.get("interact")
	if it == null or D6Js.truthy(it.get("used")):
		return
	var choice = _choice_for(game, it)
	if choice == null:
		return
	game.mode = "choice"
	game.choice = choice
	D6State.emit(game, "choiceOpen", {"kind": choice.kind})

## Panneau de choix de l'objet d'interaction `it`, selon son type (null : aucun menu).
static func _choice_for(game: Dictionary, it: Dictionary):
	var run: Dictionary = game.run
	if it.kind == "boon":
		var offers = it.get("offers")
		if offers == null:
			offers = D6Boons.roll_boon_offer(game, it.family)
			it.offers = offers
		var fam: Dictionary = D6Data.tables().boons.FAMILIES[it.family]
		var described: Array = []
		for o in offers:
			described.append(describe_boon(o))
		return {"kind": "boon", "family": it.family, "familyName": fam.name, "color": fam.color, "options": described}
	if it.kind == "loot":
		return {"kind": "loot", "item": describe_item(it.item), "equipped": describe_item(run.items.get(it.item.slot)), "salvage": D6Loot.salvage_value(game, it.item), "wieldable": can_wield(game, it.item)}
	if it.kind == "shop":
		var shown: Array = []
		for o in it.offers:
			var item = o.get("item")
			var entry: Dictionary = o.duplicate()
			entry.item = describe_item(item) if D6Js.truthy(item) else null
			entry.equipped = describe_item(run.items.get(item.slot)) if D6Js.truthy(item) else null
			shown.append(entry)
		return {"kind": "shop", "gold": run.gold, "offers": shown}
	if it.kind == "event":
		return _event_choice(game, it)
	if D6Data.tables().calm_rooms.CALM_KINDS.has(it.kind):
		return D6CalmRooms.describe_calm(game, it) # chambre forte, fontaine de repos (calm_rooms)
	return null

static func _event_def(id):
	for e in D6Data.tables().run.EVENTS:
		if e.id == id:
			return e
	return null

static func _event_choice(game: Dictionary, it: Dictionary) -> Dictionary:
	var ev: Dictionary = _event_def(it.event)
	var options: Array = []
	for o in ev.options:
		options.append({"label": _option_label(game, o), "disabled": _option_blocked(game, o)})
	return {"kind": "event", "title": ev.title, "text": ev.text, "options": options}

## Forge des regrets : la bénédiction fondue (la moins avancée) et celle qui en profite (la plus
## avancée des autres), parmi celles qui ont des niveaux ; la première à égalité. Null s'il n'y
## en a pas deux.
static func forge_targets(game: Dictionary):
	var pool: Array = []
	for b in game.run.boons:
		var d = D6Boons.boon_def(b.id)
		if d != null and not D6Js.truthy(d.get("noScale")):
			pool.append(b)
	if pool.size() < 2:
		return null
	var lost: Dictionary = pool[0]
	for b in pool:
		if b.level < lost.level:
			lost = b
	var gained = null
	for b in pool:
		if not is_same(b, lost) and (gained == null or b.level > gained.level):
			gained = b
	return {"lost": lost, "gained": gained}

## Une option d'autel que le héros ne peut pas payer (ou qui ne lui donnerait rien) est grisée.
static func _option_blocked(game: Dictionary, o: Dictionary) -> bool:
	var run: Dictionary = game.run
	var p: Dictionary = game.player
	var cost = o.get("cost")
	if D6Js.truthy(cost) and run.gold < cost:
		return true
	var souls = o.get("souls")
	if D6Js.truthy(souls) and game.meta.souls < souls:
		return true
	match o.effect:
		"bloodBoon":
			return _blood_hp(p, o) >= p.hp # à 1 PV il n'y a plus de sang à offrir
		"gadgetCharge":
			return D6Loadout.gadgets_full(game) # tous les gadgets équipés pleins, ou aucun gadget
		"superToHp":
			return p.superCharge < o.need / 100.0
		"hpToSuper":
			return p.superCharge >= 1.0 or p.hp <= MIN_HP
		"bloodSouls", "cursedChest":
			return p.hp <= MIN_HP # plus de PV à donner : l'option serait gratuite
		"reforge":
			return forge_targets(game) == null
		"pact":
			for b in run.boons:
				if b.id == o.pact:
					return true
			return false
	return false

## PV du héros après l'offrande de l'autel de sang (`o.pct` % de ses PV max) : jamais mortelle.
static func _blood_hp(p: Dictionary, o: Dictionary) -> float:
	return maxf(MIN_HP, D6Js.jround(p.hp - p.maxHp * (o.pct / 100.0)))

## String.replace de JavaScript avec un motif texte : seule la 1re occurrence est remplacée.
static func _replace_first(text: String, what: String, by: String) -> String:
	var at := text.find(what)
	if at < 0:
		return text
	return text.substr(0, at) + by + text.substr(at + what.length())

## Libellé d'une option d'autel : chaque {champ} est remplacé par le nombre du même nom dans
## l'option (celui que lit son effet : _apply_event) ; {lost} et {gained} par les bénédictions que
## la Forge fondrait et approfondirait.
static func _option_label(game: Dictionary, o: Dictionary) -> String:
	var label: String = o.label
	for k in o:
		var v = o[k]
		if v is float or v is int:
			label = _replace_first(label, "{%s}" % k, D6Js.num_str(v))
	if o.effect == "reforge":
		var f = forge_targets(game)
		label = _replace_first(label, "{lost}", ("« %s »" % D6Boons.boon_def(f.lost.id).name) if f != null else "votre bénédiction la moins avancée")
		label = _replace_first(label, "{gained}", ("« %s »" % D6Boons.boon_def(f.gained.id).name) if f != null else "la plus avancée")
	return label

static func describe_boon(o: Dictionary) -> Dictionary:
	var def: Dictionary = D6Boons.boon_def(o.id)
	var families: Dictionary = D6Data.tables().boons.FAMILIES
	var rar = null
	for r in D6Data.tables().boons.RARITIES:
		if r.id == o.rarity:
			rar = r
			break
	var fam = families[def.family] if D6Js.truthy(def.get("family")) else null
	var color = "#ffffff"
	if fam != null and fam.get("color") != null:
		color = fam.color
	var family_name = null
	if fam != null and fam.get("name") != null:
		family_name = fam.name
	else:
		var names: Array = []
		for f in def.families:
			names.append(families[f].name)
		family_name = " + ".join(names)
	return {
		"id": o.id,
		"name": def.name,
		"text": D6Boons.boon_text(def, o.rarity),
		"rarity": o.rarity,
		"rarityName": rar.name,
		"slot": def.slot,
		"level": o.get("level"),
		"duo": D6Js.truthy(def.get("families")),
		"color": color,
		"familyName": family_name,
	}

## Une arme ne se manie que par sa classe (le coffre la garde pour plus tard).
static func can_wield(game: Dictionary, item: Dictionary) -> bool:
	if item.slot != "arme":
		return true
	var classes: Dictionary = game.tuning.classes
	var kit = game.get("kit")
	var c = null
	if kit != null and kit.get("classId") != null:
		c = classes.get(kit.classId)
	if c == null:
		c = classes[classes.keys()[0]]
	return c.weapons.has(D6Js.nz(item.get("weaponType"), "lame"))

static func describe_item(item):
	if not D6Js.truthy(item):
		return null
	var loot: Dictionary = D6Data.tables().loot
	var rar = null
	for r in loot.ITEM_RARITIES:
		if r.id == item.rarity:
			rar = r
			break
	var power = null
	if D6Js.truthy(item.get("power")):
		for pw in loot.LEGENDARY_POWERS:
			if pw.id == item.power:
				power = pw
				break
	var lines: Array = []
	var base_line = D6Loot.base_text(item)
	if D6Js.truthy(base_line):
		lines.append(base_line)
	for a in item.affixes:
		var line = D6Loot.affix_text(a)
		if D6Js.truthy(line):
			lines.append(line)
	return {
		"id": item.get("id"),
		"slot": item.slot,
		"slotName": loot.SLOT_NAMES.get(item.slot),
		"weaponType": item.get("weaponType"),
		"name": item.get("name"),
		"rarity": item.rarity,
		"rarityName": rar.name,
		"color": rar.color,
		"level": item.get("level"),
		"lines": lines,
		"power": null if power == null else power.get("text"),
		"score": item.get("score"),
	}

static func _roll_shop(game: Dictionary) -> Array:
	var e: Dictionary = game.tuning.economy
	var fam = D6Boons.random_family(game)
	var item = D6Loot.random_shop_item(game)
	var boon = D6Boons.roll_boon_offer(game, fam)[0]
	var bd: Dictionary = describe_boon(boon)
	return [
		{"kind": "heal", "price": e.shopHealPrice, "label": "Élixir de sang", "text": "Rend %s %% des PV." % D6Js.num_str(D6Js.jround(e.shopHeal * 100.0)), "sold": false},
		{"kind": "boon", "price": e.shopBoonPrice, "label": bd.name, "text": bd.text, "boon": boon, "color": D6Data.tables().boons.FAMILIES[fam].color, "sold": false},
		{"kind": "item", "price": D6Loot.price_of(game, item), "label": item.name, "text": "", "item": item, "sold": false},
	]

## arr[index] de JavaScript : null si l'index est absent, non entier ou hors du tableau.
static func _at(arr, index):
	if not (arr is Array) or (typeof(index) != TYPE_INT and typeof(index) != TYPE_FLOAT):
		return null
	var f := float(index)
	if f != floorf(f) or f < 0.0 or f >= arr.size():
		return null
	return arr[int(f)]

## Array.includes pour un nombre : en GDScript, has(1.0) ne trouve pas l'entier 1.
static func _has_num(arr: Array, v) -> bool:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return false
	for x in arr:
		if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and x == v:
			return true
	return false

## Une commande est un dictionnaire {type, index?, floor?}. Refusée : rend false, ne change rien.
static func apply_command(game: Dictionary, cmd: Dictionary) -> bool:
	var type := str(cmd.get("type"))
	if type == "respawn":
		return respawn(game, cmd.get("floor"))
	if type == "returnToTown":
		# Depuis l'écran de mort (Charon a déjà pris sa part), l'écran de victoire, ou au portail
		# ouvert après un Gardien. Jamais en plein combat : quitter un run en cours, c'est
		# « abandon » (taxé comme une mort).
		var portal := false
		if game.mode == "play":
			for d in game.room.doors:
				if d.reward == "town" and D6Js.truthy(d.get("open")):
					portal = true
					break
		if game.mode != "dead" and game.mode != "victory" and not portal:
			return false
		return return_to_town(game)
	if type == "abandon":
		# Abandonner = mourir : Charon prend sa part, le temporaire est perdu, retour en Ville.
		if game.mode != "play" and game.mode != "choice":
			return false
		on_death(game)
		game.mode = "play"
		return return_to_town(game)
	if game.mode != "choice" or not D6Js.truthy(game.get("choice")):
		return false
	return _apply_choice(game, type, cmd.get("index"))

## Commande de menu (mode 'choice') : selon le panneau ouvert.
static func _apply_choice(game: Dictionary, type: String, index) -> bool:
	var it = game.room.interact
	var ch: Dictionary = game.choice
	if ch.kind == "boon" and type == "choose":
		var offer = _at(it.get("offers"), index)
		if offer == null:
			return false
		D6Boons.add_boon(game.run, offer)
		D6Stats.recompute_stats(game)
		D6State.emit(game, "boonGain", {"id": offer.id, "rarity": offer.rarity})
		return _close_choice(game)
	if ch.kind == "loot":
		return _apply_loot(game, it, type)
	if ch.kind == "shop":
		return _apply_shop(game, it, type, index)
	if D6Data.tables().calm_rooms.CALM_KINDS.has(ch.kind) and type == "choose":
		var res = D6CalmRooms.apply_calm(game, it, index)
		if not D6Js.truthy(res):
			return false
		if res == "replaced":
			# Objet ou relique choisi : il attend d'être touché, les portes attendent ce choix-là.
			game.mode = "play"
			game.choice = null
			return true
		return _close_choice(game)
	if ch.kind == "event" and type == "choose":
		var ev: Dictionary = _event_def(it.event)
		var opt = _at(ev.options, index)
		if opt == null:
			return false
		var shown = _at(ch.options, index)
		if shown != null and D6Js.truthy(shown.get("disabled")):
			return false
		if _apply_event(game, opt):
			# Le coffre maudit a posé un butin à ramasser : les portes attendent ce choix-là.
			game.mode = "play"
			game.choice = null
			return true
		return _close_choice(game)
	return false

## Butin trouvé : équiper, ranger au coffre, ou recycler.
static func _apply_loot(game: Dictionary, it: Dictionary, type: String) -> bool:
	var run: Dictionary = game.run
	var p: Dictionary = game.player
	if type == "equip":
		if not can_wield(game, it.item):
			return false
		# L'objet porté n'est jamais perdu : il part au coffre (Ville).
		var old = run.items.get(it.item.slot)
		if D6Js.truthy(old):
			D6Profile.stash_loot(game.meta, old)
		_wear(game, it.item)
		D6Stats.recompute_stats(game)
		D6State.emit(game, "equip", {"slot": it.item.slot, "rarity": it.item.rarity})
		return _close_choice(game)
	if type == "stash":
		D6Profile.stash_loot(game.meta, it.item)
		D6State.emit(game, "stash", {"slot": it.item.slot, "rarity": it.item.rarity})
		return _close_choice(game)
	if type == "salvage":
		run.gold += D6Loot.salvage_value(game, it.item)
		D6State.emit(game, "gold", {"x": p.x, "y": p.y, "amount": D6Loot.salvage_value(game, it.item)})
		return _close_choice(game)
	return false

## L'objet rejoint l'équipement du PROFIL (run.items) : il y reçoit son identifiant tout de suite,
## comme un objet rangé au coffre — le profil en mémoire est celui qu'on relira du disque.
static func _wear(game: Dictionary, item: Dictionary) -> void:
	D6Profile.ensure_uid(game.meta, item)
	game.run.items[item.slot] = item

## Marchand : fermer, ou acheter l'offre `index`.
static func _apply_shop(game: Dictionary, it: Dictionary, type: String, index) -> bool:
	var run: Dictionary = game.run
	var p: Dictionary = game.player
	if type == "close":
		return _close_choice(game)
	if type != "choose":
		return false
	var offer = _at(it.offers, index)
	if offer == null or D6Js.truthy(offer.get("sold")) or run.gold < offer.price:
		return false
	run.gold -= offer.price
	offer.sold = true
	if offer.kind == "heal":
		D6Combat.heal_player(game, p.maxHp * game.tuning.economy.shopHeal, true)
	if offer.kind == "boon":
		D6Boons.add_boon(run, offer.boon)
	if offer.kind == "item":
		if can_wield(game, offer.item):
			var old = run.items.get(offer.item.slot)
			if D6Js.truthy(old):
				D6Profile.stash_loot(game.meta, old)
			_wear(game, offer.item)
		else:
			D6Profile.stash_loot(game.meta, offer.item)
	sync_purse(game)
	D6Stats.recompute_stats(game)
	D6State.emit(game, "buy", {"kind": offer.kind})
	_open_shop_refresh(game)
	return true

static func _open_shop_refresh(game: Dictionary) -> void:
	game.mode = "play"
	game.room.interact.used = false
	open_interact(game)

## Effet d'une option d'autel. Tous ses nombres sont dans l'option (data/autels.json), que son
## libellé reprend par {champ} : aucun n'est écrit ici. Rend true si un butin a été posé (le menu
## se ferme sans ouvrir les portes).
static func _apply_event(game: Dictionary, opt: Dictionary) -> bool:
	var run: Dictionary = game.run
	var p: Dictionary = game.player
	match opt.effect:
		"bloodBoon", "mammonBoon", "soulBoon":
			_event_boon(game, opt)
		"heal":
			D6Combat.heal_player(game, p.maxHp * (opt.pct / 100.0), true)
		"gadgetCharge":
			D6Loadout.grant_gadget_charges(game, opt.gain) # à chaque gadget équipé
		"cursedChest":
			_event_chest(game, opt)
			return true
		"gold":
			run.gold += opt.gain
			D6State.emit(game, "gold", {"x": p.x, "y": p.y, "amount": opt.gain})
		"bloodSouls":
			# Des PV de ce run contre des Âmes qui resteront (l'inverse du Registre : _event_boon).
			p.hp = maxf(MIN_HP, p.hp - opt.hp)
			game.meta.souls += opt.gain
			game.telemetry.soulsEarned += opt.gain
			D6State.emit(game, "souls", {"x": p.x, "y": p.y, "amount": opt.gain})
		"reforge":
			var f: Dictionary = forge_targets(game)
			var lost: Dictionary = f.lost
			run.boons = run.boons.filter(func(b): return not is_same(b, lost))
			f.gained.level += opt.levels
			D6State.emit(game, "boonGain", {"id": f.gained.id, "rarity": f.gained.rarity})
		"pact":
			D6Boons.add_boon(run, {"id": opt.pact, "rarity": "commun"})
			D6State.emit(game, "boonGain", {"id": opt.pact, "rarity": "commun"})
		"superToHp":
			p.superCharge = 0.0
			D6Combat.heal_player(game, p.maxHp * (opt.pct / 100.0), true)
		"hpToSuper":
			p.hp = maxf(MIN_HP, p.hp - opt.hp)
			p.superCharge = 1.0
			D6State.emit(game, "superReady")
	D6Stats.recompute_stats(game)
	return false

## Autels qui donnent une bénédiction contre un prix : le prix d'abord — une part des PV (autel de
## sang), de l'or (Mammon) ou des Âmes du profil (Registre : le PERMANENT paie le TEMPORAIRE) —,
## puis un tirage dans la famille de l'option (au hasard si elle n'en nomme pas), relevé à la
## rareté promise par l'option : un tirage meilleur le reste.
static func _event_boon(game: Dictionary, opt: Dictionary) -> void:
	var run: Dictionary = game.run
	match opt.effect:
		"bloodBoon":
			game.player.hp = _blood_hp(game.player, opt)
		"mammonBoon":
			run.gold -= opt.cost
		"soulBoon":
			game.meta.souls -= opt.souls
	var fam = opt.get("family")
	if fam == null:
		fam = D6Boons.random_family(game)
	var offer = D6Boons.roll_boon_offer(game, fam)[0]
	if opt.get("rarity") != null:
		offer.rarity = D6Boons.best_rarity(offer.rarity, opt.rarity)
	D6Boons.add_boon(run, offer)
	D6State.emit(game, "boonGain", {"id": offer.id, "rarity": offer.rarity})

## Coffre maudit : des PV contre un objet de la rareté de l'option, posé à ramasser.
static func _event_chest(game: Dictionary, opt: Dictionary) -> void:
	var p: Dictionary = game.player
	p.hp = maxf(MIN_HP, p.hp - opt.hp)
	var item = D6Loot.generate_item(game, {"rarity": opt.rarity})
	var spot: Dictionary = D6Room.reward_spot(game.room)
	game.room.interact = {"kind": "loot", "x": spot.x, "y": spot.y, "r": game.tuning.room.rewardRadius, "used": false, "item": item}
	D6Stats.recompute_stats(game)

static func _close_choice(game: Dictionary) -> bool:
	game.mode = "play"
	game.choice = null
	if D6Js.truthy(game.room.get("interact")):
		game.room.interact.used = true
	_open_doors(game)
	D6State.emit(game, "choiceClose")
	return true

# ---------------------------------------------------------------- mort, reprise, Ville

## Mort du héros (appelé une fois, quand l'écran de mort s'ouvre) : Charon prélève sa part de
## la bourse, le récapitulatif dit ce qui est PERDU (temporaire) et ce qui est GARDÉ (permanent).
static func on_death(game: Dictionary) -> void:
	var run: Dictionary = game.run
	var meta: Dictionary = game.meta
	var keep: float = minf(1.0, game.tuning.economy.deathGoldKeep + D6Js.nz(game.player.stats.get("deathGoldKeepBonus"), 0.0))
	var before = run.gold
	if not game.sandbox and not game.practice:
		run.gold = floorf(run.gold * keep)
		meta.stats.deaths += 1.0
	var boon_names: Array = []
	for b in run.boons:
		var def = D6Boons.boon_def(b.id)
		boon_names.append(b.id if def == null or def.get("name") == null else def.name)
	run.deathRecap = {
		"floor": run.floor,
		"boonsLost": float(run.boons.size()),
		"boonNames": boon_names,
		"goldLost": before - run.gold,
		"gold": run.gold,
		"souls": meta.souls,
		"soulsEarned": game.telemetry.soulsEarned,
		"tree": tree_recap(game), # expérience gagnée, niveaux passés, niveau et points de la classe
		"checkpoint": last_checkpoint(game),
	}
	sync_purse(game)

## Bilan de la descente côté ARBRE, pour l'affichage (mort, victoire, retour) : {classId, xpEarned,
## levelsGained, level, points}. L'expérience est déjà au profil : elle y est versée à chaque ennemi tué.
static func tree_recap(game: Dictionary) -> Dictionary:
	return Arbre.recap(game)

## Dernier checkpoint débloqué (point de reprise par défaut).
static func last_checkpoint(game: Dictionary):
	var cps: Array = game.meta.checkpoints
	if cps.is_empty():
		return 1.0
	return D6Js.nz(cps[cps.size() - 1], 1.0)

static func _revive(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	D6KitSupers.reset(game, "reprise")
	Neuves.reset(game)
	D6Stats.recompute_stats(game)
	p.hp = p.maxHp
	p.superCharge = D6Js.nz(t["super"].get("startCharge"), 0.0)
	p.dashCharges = t.dash.charges + p.stats.dashChargesBonus
	D6Loadout.refill_gadgets(game)
	for st in p.slots:
		st.cd = 0.0
	p.superHold = 0.0
	p.superArm = false
	p.iframes = 1.0
	p.freeze = 0.0
	p.state = "free"
	game.mode = "play"
	game.choice = null
	game.deathT = 0.0

## Reprise après la mort : au checkpoint demandé (s'il est débloqué), sinon au DERNIER.
## Le TEMPORAIRE repart de zéro (bénédictions vidées) ; le PERMANENT reste (équipement, classe,
## kit, Âmes, déblocages). La bourse a déjà payé Charon (on_death).
static func respawn(game: Dictionary, floor_num = null) -> bool:
	if game.mode != "dead":
		return false
	var cps: Array = game.meta.checkpoints
	var target = floor_num if _has_num(cps, floor_num) else last_checkpoint(game)
	var run: Dictionary = game.run
	if game.sandbox:
		# Arène d'essai : on recommence l'arène, jamais un checkpoint profond.
		_revive(game)
		D6State.emit(game, "respawn", {"floor": 1.0})
		enter_floor(game, 1.0, {"reward": "boon"})
		return true
	if game.practice:
		# Entraînement : le même Gardien, aussitôt.
		run.boons = []
		_revive(game)
		D6State.emit(game, "respawn", {"floor": run.floor})
		enter_floor(game, run.floor, null)
		return true
	run.boons = []
	run.streak = 0.0
	_revive(game)
	var recap = run.get("deathRecap")
	var boons_lost = 0.0
	if recap != null:
		boons_lost = D6Js.nz(recap.get("boonsLost"), 0.0)
	D6State.emit(game, "respawn", {"floor": target, "boonsLost": boons_lost})
	enter_floor(game, target, {"reward": "boon", "family": D6Boons.random_family(game)})
	return true

## Fin du run et retour en Ville : depuis l'écran de mort, l'écran de victoire, ou par le portail
## qui suit un Gardien. Le temporaire est abandonné avec la partie ; main sauvegarde le profil.
static func return_to_town(game: Dictionary) -> bool:
	if game.mode != "dead" and game.mode != "play" and game.mode != "victory":
		return false
	sync_purse(game)
	game.mode = "town"
	game.choice = null
	D6State.emit(game, "returnTown", {"floor": game.run.floor, "checkpoint": last_checkpoint(game)})
	return true
