extends RefCounted
## Portage de tools/bots.mjs — MENUS (mode 'choice') : bénédiction, butin, boutique, événement.
## Exercé seulement par les oracles de jouabilité (outils/solvabilite.gd, outils/classes.gd) : les
## parties de référence résolvent leurs menus autrement (references/partie.gd, _menu_candidates).

const Base = preload("res://outils/bots/base.gd")

const LOW_HP_SHOP := 0.6 # achète le soin sous 60 % de PV
const POLICY_SALT := {"skilled": 1, "noDash": 2, "masher": 3}
const FALLBACK_COMMANDS := [
	{"type": "close"}, {"type": "salvage"},
	{"type": "choose", "index": 0.0}, {"type": "choose", "index": 1.0}, {"type": "choose", "index": 2.0},
]

static func _boon_index(game: Dictionary, policy_name: String, count: int) -> float:
	return float(Base.mix_hash([game.seed, game.run.floor, POLICY_SALT.get(policy_name, 0), game.run.boons.size()]) % count)

static func _shop_command(game: Dictionary, ch: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var offers: Array = ch.offers
	for i in offers.size():
		var o: Dictionary = offers[i]
		if o.get("kind") == "heal" and not D6Js.truthy(o.get("sold")):
			if p.hp < p.maxHp * LOW_HP_SHOP and game.run.gold >= o.price:
				return {"type": "choose", "index": float(i)}
			break # findIndex : seule la PREMIÈRE offre de soin non vendue compte
	return {"type": "close"}

static func _event_command(ch: Dictionary) -> Dictionary:
	var options: Array = ch.options
	var i := 0
	if not options.is_empty() and D6Js.truthy(options[0].get("disabled")):
		i = -1
		for j in options.size():
			if not D6Js.truthy(options[j].get("disabled")):
				i = j
				break
	return {"type": "choose", "index": float(maxi(0, i))}

static func _primary_command(game: Dictionary, policy_name: String) -> Dictionary:
	var ch: Dictionary = game.choice
	if ch.kind == "boon":
		return {"type": "choose", "index": _boon_index(game, policy_name, ch.options.size())}
	if ch.kind == "loot":
		var equipped = ch.get("equipped")
		var cur: float = equipped.score if D6Js.truthy(equipped) else -INF
		return {"type": "equip" if ch.item.score > cur else "salvage"}
	if ch.kind == "shop":
		return _shop_command(game, ch)
	if ch.kind == "event":
		return _event_command(ch)
	return {"type": "close"}

## Les commandes que le bot enverrait au menu ouvert, dans l'ordre d'essai (la première acceptée
## gagne), SANS les appliquer : pour l'appelant qui passe par une autre porte que apply_command
## (jeu/essai/test_parcours.gd les envoie par `app.commande`, comme un écran). [] hors menu.
static func choice_commands(game: Dictionary, policy_name: String) -> Array:
	if game.mode != "choice" or not D6Js.truthy(game.get("choice")):
		return []
	return [_primary_command(game, policy_name)] + FALLBACK_COMMANDS

## Résout le menu ouvert (game.mode == 'choice') via apply_command. Rend true si une
## commande a été acceptée. Repli sur des commandes génériques si la première échoue.
static func resolve_choice(game: Dictionary, policy_name: String) -> bool:
	if game.mode != "choice" or not D6Js.truthy(game.get("choice")):
		return false
	if D6Game.apply_command(game, _primary_command(game, policy_name)):
		return true
	for cmd in FALLBACK_COMMANDS:
		if game.mode != "choice":
			return true
		if D6Game.apply_command(game, cmd):
			return true
	return false
