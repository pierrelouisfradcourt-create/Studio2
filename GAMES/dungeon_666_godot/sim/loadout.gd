class_name D6Loadout
extends RefCounted
## Portage de src/sim/loadout.mjs.
## Résolution du KIT équipé : classe + arme portée + compétence + gadget + Super.
##
## Les blocs actifs de la copie de tuning de la partie deviennent des RÉFÉRENCES vers l'entrée
## choisie (tuning.combo est tuning.weapons[type].combo, etc.). Le reste de la simulation lit
## toujours tuning.combo / tuning.skill / tuning.gadget / tuning.super, sans connaître les classes.

const DEFAULT_WEAPON := "lame"
const COMBO_EXPIRED := 99.0 # s : valeur de départ de player.comboTimer (state), « aucun enchaînement en cours »

## game.meta.loadout?.<key> : null si le loadout ou la clé manque.
static func _loadout_field(game: Dictionary, key: String):
	var l = game.meta.get("loadout")
	return l.get(key) if l is Dictionary else null

static func class_of(game: Dictionary) -> Dictionary:
	var t: Dictionary = game.tuning
	var c = t.classes.get(_loadout_field(game, "classId"))
	return c if c != null else t.classes[t.classes.keys()[0]]

static func class_id_of(game: Dictionary):
	var t: Dictionary = game.tuning
	var id = _loadout_field(game, "classId")
	return id if D6Js.truthy(t.classes.get(id)) else t.classes.keys()[0]

## Type d'arme porté : celui de l'objet d'arme équipé, sinon l'arme de départ de la classe.
static func weapon_type_of(game: Dictionary):
	var t: Dictionary = game.tuning
	var arme = game.run.items.get("arme")
	var wt = arme.get("weaponType") if arme is Dictionary else null
	if D6Js.truthy(wt) and D6Js.truthy(t.weapons.get(wt)):
		return wt
	var weapons: Array = class_of(game).weapons
	return weapons[0] if not weapons.is_empty() and weapons[0] != null else DEFAULT_WEAPON

## Autre arme en main : l'enchaînement repart du coup 1. Sans cela, le rang gardé de l'ancienne
## arme (comboIndex) peut dépasser le combo de la nouvelle (4 coups des Dagues -> 3 de la Lame).
static func _reset_combo_if_changed(game: Dictionary, weapon: Dictionary) -> void:
	var p = game.get("player")
	var held = game.tuning.get("weapon")
	if not (p is Dictionary) or held == null or is_same(held, weapon):
		return
	p.comboIndex = 0.0
	p.comboTimer = COMBO_EXPIRED

## (Re)branche le kit actif. Appelé à la création de la partie et à chaque changement d'arme.
static func resolve_kit(game: Dictionary) -> Dictionary:
	var t: Dictionary = game.tuning
	var c := class_of(game)
	var w: Dictionary = t.weapons[weapon_type_of(game)]
	_reset_combo_if_changed(game, w)
	t.combo = w.combo
	t.dashStrike = w.dashStrike
	t.weapon = w
	var l_skill = _loadout_field(game, "skillId")
	var l_gadget = _loadout_field(game, "gadgetId")
	var skill_id = l_skill if c.skills.has(l_skill) and D6Js.truthy(t.skills.get(l_skill)) else c.skills[0]
	var gadget_id = l_gadget if c.gadgets.has(l_gadget) and D6Js.truthy(t.gadgets.get(l_gadget)) else c.gadgets[0]
	t.skill = t.skills[skill_id]
	t.gadget = t.gadgets[gadget_id]
	t["super"] = D6Js.nz(t.supers.get(c.get("super")), t.get("super"))
	game.kit = {"classId": class_id_of(game), "weaponType": weapon_type_of(game), "skillId": skill_id, "gadgetId": gadget_id, "superId": c.get("super")}
	return game.kit
