class_name D6CalmRooms
extends RefCounted
## Portage de src/sim/calm_rooms.mjs.
## SALLES CALMES réutilisables (sans combat), placées par le plan de section (sections) :
##   treasure — « Chambre forte » : un coffre scellé, UN choix parmi trois trésors annoncés
##              (un objet d'équipement, une bourse, une relique = bénédiction) ;
##   rest     — « Fontaine du Léthé » : UN choix parmi trois grâces (boire : soin ; méditer : une
##              bénédiction possédée gagne un niveau ; fioles : gadget et Super rechargés).
## Le contenu est tiré à l'ENTRÉE dans la salle (le panneau l'annonce, rien de caché). L'objet
## rejoint l'équipement PERMANENT comme tout butin ; or, bénédiction, soin et niveaux restent
## TEMPORAIRES (la mort les reprend, comme le reste du run).
##
## Contrat avec run : setup_calm_room à l'entrée, describe_calm pour le panneau (mode 'choice'),
## apply_calm(index) rend 'close' (choix fait), 'replaced' (l'objet d'interaction est remplacé par
## un butin ou une bénédiction à toucher) ou false (choix refusé).
## CALM_KINDS se lit dans D6Data.tables().calm_rooms.

const TREASURE_COLOR := "#ffb43c"
const REST_COLOR := "#6dd8ff"
const PERCENT := 100.0

## Rang d'une rareté d'objet dans ITEM_RARITIES (-1 si inconnue).
static func _rarity_rank(id) -> int:
	var rarities: Array = D6Data.tables().loot.ITEM_RARITIES
	for i in rarities.size():
		if rarities[i].id == id:
			return i
	return -1

static func _item_rarity(id):
	for r in D6Data.tables().loot.ITEM_RARITIES:
		if r.id == id:
			return r
	return null

## Tire le contenu de l'objet d'interaction `it` d'une salle calme (à l'entrée dans la salle).
static func setup_calm_room(game: Dictionary, it: Dictionary) -> void:
	if it.kind != "treasure":
		return
	var tr: Dictionary = game.tuning.economy.treasure
	var rarities: Array = D6Data.tables().loot.ITEM_RARITIES
	var min_rank := _rarity_rank(tr.minRarity)
	var rolled = D6Loot.roll_rarity(game, tr.rarityBonus)
	var rank := maxi(min_rank, _rarity_rank(rolled))
	it.item = D6Loot.generate_item(game, {"rarity": rarities[rank].id})
	# La bourse tombe en goldPickups pièces égales : le montant ANNONCÉ est celui qui sera versé.
	var drawn: float = D6Rng.rand_int(game.rng.gen, tr.gold[0], tr.gold[1])
	var each: float = maxf(1.0, D6Js.jround((drawn * game.player.stats.goldFindMult) / tr.goldPickups))
	it.gold = each * tr.goldPickups
	it.family = D6Boons.random_family(game)

## Bénédiction que la méditation approfondit : la moins avancée (la première à égalité). Jamais
## une bénédiction `noScale` (Envol : « +1 charge de dash ») : elle n'a pas de niveau.
static func _meditation_target(game: Dictionary):
	var best = null
	for b in game.run.boons:
		var def = D6Boons.boon_def(b.id)
		if def != null and D6Js.truthy(def.get("noScale")):
			continue
		if best == null or b.level < best.level:
			best = b
	return best

static func _treasure_options(_game: Dictionary, it: Dictionary) -> Array:
	var rar = _item_rarity(it.item.rarity)
	var fam: Dictionary = D6Data.tables().boons.FAMILIES[it.family]
	var slot_name = D6Data.tables().loot.SLOT_NAMES.get(it.item.slot)
	return [
		{"id": "objet", "kicker": "Objet · " + str(rar.name) + " · " + str(slot_name), "label": it.item.name, "text": "Équipement PERMANENT : il rejoint votre équipement ou le coffre de la Ville.", "color": rar.color, "disabled": false},
		{"id": "bourse", "kicker": "Bourse", "label": "+" + D6Js.num_str(it.gold) + " or", "text": "L'or suit le héros ; Charon en prend sa part à chaque mort.", "color": "#ffd23c", "disabled": false},
		{"id": "relique", "kicker": "Relique · " + str(fam.name), "label": "Bénédiction", "text": "Un don du péché, TEMPORAIRE : perdu à la mort.", "color": fam.color, "disabled": false},
	]

static func _rest_options(game: Dictionary) -> Array:
	var p: Dictionary = game.player
	var r: Dictionary = game.tuning.economy.rest
	var heal: float = D6Js.jround(p.maxHp * r.heal)
	var target = _meditation_target(game)
	var boon_name = null
	if target != null:
		var def = D6Boons.boon_def(target.id)
		boon_name = target.id if def == null or def.get("name") == null else def.name
	var full: bool = D6Loadout.gadgets_full(game) and p.superCharge >= 1.0
	return [
		# jamais grisé : un choix reste toujours possible
		{"id": "boire", "kicker": "Soin", "label": "Boire · +" + D6Js.num_str(heal) + " PV", "text": "Rend " + D6Js.num_str(D6Js.jround(r.heal * PERCENT)) + " % des PV.", "color": "#6dff8a", "disabled": false},
		{"id": "mediter", "kicker": "Amélioration · temporaire", "label": ("Méditer · " + str(boon_name) + " niv. " + D6Js.num_str(target.level + 1.0)) if target != null else "Méditer", "text": "Votre bénédiction la moins avancée gagne un niveau." if target != null else "Aucune bénédiction à approfondir.", "color": "#b98cff", "disabled": target == null},
		{"id": "fioles", "kicker": "Pouvoirs", "label": "Remplir les fioles", "text": "Charges des compétences pleines, jauge de Super +" + D6Js.num_str(D6Js.jround(r.superCharge * PERCENT)) + " %.", "color": REST_COLOR, "disabled": full},
	]

## Panneau de choix (game.choice) de l'objet d'interaction `it`.
static func describe_calm(game: Dictionary, it: Dictionary):
	if it.kind == "treasure":
		return {"kind": "treasure", "title": "Chambre forte", "text": "Un coffre scellé. Un seul de ses trois trésors vous suivra.", "color": TREASURE_COLOR, "options": _treasure_options(game, it)}
	if it.kind == "rest":
		return {"kind": "rest", "title": "Fontaine du Léthé", "text": "L'eau efface la fatigue. Elle n'accorde qu'une grâce.", "color": REST_COLOR, "options": _rest_options(game)}
	return null

## arr[index] de JavaScript : null si l'index est absent, non entier ou hors du tableau.
static func _at(arr, index):
	if not (arr is Array) or (typeof(index) != TYPE_INT and typeof(index) != TYPE_FLOAT):
		return null
	var f := float(index)
	if f != floorf(f) or f < 0.0 or f >= arr.size():
		return null
	return arr[int(f)]

## Applique l'option `index` du panneau de l'objet `it`. Rend 'close', 'replaced' ou false.
static func apply_calm(game: Dictionary, it: Dictionary, index):
	var ch = describe_calm(game, it)
	var opt = null if ch == null else _at(ch.options, index)
	if opt == null or D6Js.truthy(opt.get("disabled")):
		return false
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	match opt.id:
		"objet":
			room.interact = {"kind": "loot", "x": it.x, "y": it.y, "r": game.tuning.room.rewardRadius, "used": false, "item": it.item}
			return "replaced"
		"relique":
			room.interact = {"kind": "boon", "x": it.x, "y": it.y, "r": game.tuning.room.rewardRadius, "used": false, "family": it.family}
			return "replaced"
		"bourse":
			var n: float = game.tuning.economy.treasure.goldPickups
			var each: float = maxf(1.0, D6Js.jround(it.gold / n))
			var i := 0.0
			while i < n:
				D6Combat.spawn_pickup(game, "gold", it.x, it.y, each)
				i += 1.0
			return "close"
		"boire":
			D6Combat.heal_player(game, p.maxHp * game.tuning.economy.rest.heal, true)
			return "close"
		"mediter":
			var target = _meditation_target(game)
			D6Boons.add_boon(game.run, {"id": target.id, "rarity": target.rarity})
			D6Stats.recompute_stats(game)
			D6State.emit(game, "boonGain", {"id": target.id, "rarity": target.rarity})
			return "close"
		"fioles":
			# Tous les gadgets équipés sont remplis ; l'événement nomme le premier (aucun : 0 charge).
			D6Loadout.refill_gadgets(game)
			p.superCharge = minf(1.0, p.superCharge + game.tuning.economy.rest.superCharge)
			var slot := D6Loadout.first_gadget(game)
			var ev: Dictionary = D6State.emit(game, "gadgetCharge", {"x": p.x, "y": p.y, "charges": p.slots[slot].charges if slot >= 0 else 0.0})
			if slot >= 0:
				ev.slot = float(slot)
			return "close"
	return false
