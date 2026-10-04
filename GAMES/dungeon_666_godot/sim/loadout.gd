class_name D6Loadout
extends RefCounted
## Portage de src/sim/loadout.mjs, étendu par le combat V3.
## Résolution du KIT équipé : classe + arme portée + TROIS emplacements d'action + Super.
##
## Les blocs actifs de la copie de tuning de la partie deviennent des RÉFÉRENCES vers l'entrée
## choisie (tuning.combo est tuning.weapons[type].combo, etc.). Le reste de la simulation lit
## toujours tuning.combo / tuning.weapon / tuning.super / tuning.dash, sans connaître les classes.
##
## EMPLACEMENTS (game.kit.slots, trois identifiants ou null) : chacun porte une compétence (à
## recharge) ou un gadget (à charges) de la classe. Son état vit dans game.player.slots[i] :
## {cd, charges}. Ce module est le seul à savoir quelle sorte d'action tient un emplacement ;
## l'affichage lit slot_view, sans connaître l'intérieur.

const DEFAULT_WEAPON := "lame"
const COMBO_EXPIRED := 99.0 # s : valeur de départ de player.comboTimer (state), « aucun enchaînement en cours »
const SLOTS := 3 # emplacements d'action
const DEFAULT_MOVE := "dash" # déplacement d'une classe qui n'en nomme pas : le dash de base

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

## Sorte d'une action de la classe `c` : "skill", "gadget", ou null (inconnue, d'une autre classe).
static func action_kind(tuning: Dictionary, c: Dictionary, id):
	if id == null:
		return null
	if c.skills.has(id) and D6Js.truthy(tuning.skills.get(id)):
		return "skill"
	if c.gadgets.has(id) and D6Js.truthy(tuning.gadgets.get(id)):
		return "gadget"
	return null

## Les trois identifiants équipés (null = vide). Le profil d'une partie est déjà assaini
## (D6Profile.fix_loadout) : ici, une action inconnue de la classe ou en double laisse seulement
## son emplacement vide. Sans `slots` (profil partiel) : compétence et gadget de départ.
static func _slot_ids(game: Dictionary) -> Array:
	var c := class_of(game)
	var raw = _loadout_field(game, "slots")
	if not (raw is Array):
		return [c.skills[0], c.gadgets[0], null]
	var out: Array = []
	for i in SLOTS:
		var id = raw[i] if i < raw.size() else null
		out.append(id if action_kind(game.tuning, c, id) != null and not out.has(id) else null)
	return out

## (Re)branche le kit actif. Appelé à la création de la partie et à chaque changement d'arme.
static func resolve_kit(game: Dictionary) -> Dictionary:
	var t: Dictionary = game.tuning
	var c := class_of(game)
	t["super"] = D6Js.nz(t.supers.get(c.get("super")), t.get("super"))
	# FORME (ultime du Revenant) : tant qu'elle dure, les griffes remplacent l'arme équipée et les
	# actions de forme tiennent les trois emplacements (D6KitSupers ; kit d'origine rendu à la fin).
	var form: bool = D6KitSupers.form_of(game) != null
	var w: Dictionary = t["super"].weapon if form else t.weapons[weapon_type_of(game)]
	_reset_combo_if_changed(game, w)
	t.combo = w.combo
	t.dashStrike = w.dashStrike
	t.weapon = w
	_resolve_move(t, c)
	var slots: Array = t["super"].slots.duplicate() if form else _slot_ids(game)
	game.kit = {"classId": class_id_of(game), "weaponType": weapon_type_of(game), "slots": slots, "superId": c.get("super")}
	return game.kit

## Identifiant du déplacement de la classe jouée (clé de tuning.moves) ; le dash si elle n'en nomme pas.
static func move_id(game: Dictionary) -> String:
	var id = class_of(game).get("move")
	var moves = game.tuning.get("moves")
	return id if moves is Dictionary and moves.get(id) is Dictionary else DEFAULT_MOVE

## DÉPLACEMENT DE CLASSE (même bouton que le dash, un geste par classe : t.moves, data/classes.json).
## t.dash devient le bloc ACTIF : le dash de base (t.dashBase, gardé tel quel — c'est lui que les
## surcharges de réglage visent), recouvert par les nombres du déplacement de la classe. Pour le
## dash lui-même (Revenant), t.dash RESTE le bloc de base, sans copie.
static func _resolve_move(t: Dictionary, c: Dictionary) -> void:
	if t.get("dashBase") == null:
		t.dashBase = t.dash
	var id = c.get("move")
	var moves = t.get("moves")
	var m = moves.get(id) if moves is Dictionary and id != null else null
	if not (m is Dictionary) or D6Js.nz(m.get("kind"), DEFAULT_MOVE) == DEFAULT_MOVE:
		t.dash = t.dashBase
		return
	var active: Dictionary = t.dashBase.duplicate(true)
	active.merge(m, true)
	t.dash = active

# ---------------------------------------------------------------- emplacements d'action

## Sorte de l'action d'un emplacement : "skill" (recharge), "gadget" (charges), ou null (vide).
static func slot_kind(game: Dictionary, index: int):
	if _form_action(game, game.kit.slots[index]) != null:
		return "skill" # une action de forme se lance comme une compétence (recharge)
	return action_kind(game.tuning, class_of(game), game.kit.slots[index])

## Réglages de l'action de FORME `id` (tuning.super.actions) si la forme est en cours, sinon null.
static func _form_action(game: Dictionary, id):
	if id == null or D6KitSupers.form_of(game) == null:
		return null
	var actions = game.tuning["super"].get("actions")
	return actions.get(id) if actions is Dictionary else null

## Réglages de l'action d'un emplacement (référence vers tuning.skills / tuning.gadgets), ou null.
static func slot_def(game: Dictionary, index: int):
	var id = game.kit.slots[index]
	var form_def = _form_action(game, id)
	if form_def != null:
		return form_def
	match action_kind(game.tuning, class_of(game), id):
		"skill":
			return game.tuning.skills[id]
		"gadget":
			return game.tuning.gadgets[id]
	return null

## La compétence en cours de lancer (état 'cast' du héros) ; null si l'emplacement ne porte rien.
static func cast_def(game: Dictionary):
	return slot_def(game, int(game.player.castSlot))

## Charges maximales du gadget d'un emplacement (0 : compétence ou emplacement vide).
static func max_charges(game: Dictionary, index: int) -> float:
	if slot_kind(game, index) != "gadget":
		return 0.0
	return slot_def(game, index).chargesPerSection + game.player.stats.gadgetChargesBonus

## État neuf des emplacements à la naissance du héros : aucune recharge en cours, chaque gadget
## à ses charges de base (les bonus viennent avec les stats, la section les complète).
static func reset_slots(game: Dictionary) -> void:
	for i in SLOTS:
		var st: Dictionary = game.player.slots[i]
		st.cd = 0.0
		st.charges = slot_def(game, i).chargesPerSection if slot_kind(game, i) == "gadget" else 0.0

## Premier emplacement qui porte un gadget, ou -1.
static func first_gadget(game: Dictionary) -> int:
	for i in SLOTS:
		if slot_kind(game, i) == "gadget":
			return i
	return -1

## Vrai si aucun gadget équipé ne peut plus recevoir de charge (vrai aussi sans gadget).
static func gadgets_full(game: Dictionary) -> bool:
	for i in SLOTS:
		if slot_kind(game, i) == "gadget" and game.player.slots[i].charges < max_charges(game, i):
			return false
	return true

## Tous les gadgets équipés retrouvent leurs charges (début de section, repos, reprise).
static func refill_gadgets(game: Dictionary) -> void:
	for i in SLOTS:
		if slot_kind(game, i) == "gadget":
			var st: Dictionary = game.player.slots[i]
			st.charges = maxf(st.charges, max_charges(game, i))

## Rend `amount` charges à CHAQUE gadget équipé (null : son propre chargeOnEliteKill), sans
## dépasser son maximum. Rend le premier emplacement qui en a gagné, ou -1 (tous pleins, aucun gadget).
static func grant_gadget_charges(game: Dictionary, amount) -> int:
	var first := -1
	for i in SLOTS:
		if slot_kind(game, i) != "gadget":
			continue
		var st: Dictionary = game.player.slots[i]
		var maxi := max_charges(game, i)
		if st.charges >= maxi:
			continue
		st.charges = minf(maxi, st.charges + (slot_def(game, i).chargeOnEliteKill if amount == null else amount))
		if first < 0:
			first = i
	return first

## Ramène les charges de chaque gadget sous son maximum (le build vient de changer).
static func clamp_gadgets(game: Dictionary) -> void:
	for i in SLOTS:
		if slot_kind(game, i) == "gadget":
			var st: Dictionary = game.player.slots[i]
			st.charges = minf(st.charges, max_charges(game, i))

## Ce que l'affichage lit d'un emplacement, sans connaître l'intérieur ; null s'il est vide.
##   ready        : l'action peut partir (recharge finie, ou une charge au moins)
##   cooldownFrac : 0 = prêt, 1 = vient de servir (toujours 0 pour un gadget)
##   charges, maxCharges : charges restantes et maximum d'un gadget ; null pour une compétence
##   aimed        : l'action se vise (toute compétence ; un gadget LANCÉ, comme la bombe ; une
##                  action qui dit `aimed: false` ne se vise pas : hurlement, embrasement)
## Pendant la Forme du Damné, les trois emplacements rendent les actions de FORME.
static func slot_view(game: Dictionary, index: int):
	var def = slot_def(game, index)
	if def == null:
		return null
	var kind = slot_kind(game, index)
	var st: Dictionary = game.player.slots[index]
	var gadget: bool = kind == "gadget"
	var full: float = 0.0 if gadget else def.cooldown * game.player.stats.skillCooldownMult
	return {
		"id": game.kit.slots[index], "name": def.name, "icon": D6Js.nz(def.get("icon"), kind), "kind": kind,
		"ready": st.charges > 0.0 if gadget else st.cd <= 0.0,
		"cooldownFrac": D6Geo.clampv(st.cd / full, 0.0, 1.0) if full > 0.0 else 0.0,
		"charges": st.charges if gadget else null,
		"maxCharges": max_charges(game, index) if gadget else null,
		"aimed": D6Js.nz(def.get("aimed"), not gadget or def.get("throwDist") != null),
	}
