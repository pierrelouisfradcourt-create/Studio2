extends RefCounted
## DÉFAUTS DE RÈGLES, quatrième lot (2026-10-04) : voir DEFAUTS.md.
## Défaut 19 : un objet ÉQUIPÉ en donjon (butin pris, objet acheté au marchand) entrait dans le
## profil sans identifiant (`uid`) ; il ne le recevait qu'à la relecture du profil
## (D6Profile.sanitize_profile). Le profil en mémoire et le profil relu différaient donc. Les trois
## tests sont rouges sur le code d'avant, verts après.

const SEED := 31.0
const RICH := 1000.0 # or : de quoi payer l'objet du marchand
const PRICE := 10.0

## Tous les objets du profil : l'équipement porté, puis le coffre.
static func _items(meta: Dictionary) -> Array:
	var out: Array = []
	for slot in meta.equipment:
		if meta.equipment[slot] != null:
			out.append(meta.equipment[slot])
	out.append_array(meta.stash)
	return out

static func _has_uid(item) -> bool:
	return item is Dictionary and item.get("uid") is String and item.uid != ""

## Les identifiants du profil sont tous posés et tous différents.
static func _uids_ok(meta: Dictionary) -> bool:
	var seen := {}
	for it in _items(meta):
		if not _has_uid(it) or seen.has(it.uid):
			return false
		seen[it.uid] = true
	return true

## Un butin rare du type `slot` posé sous les pieds du héros, son menu ouvert. Rend l'objet.
static func _open_loot(g: Dictionary, slot: String) -> Dictionary:
	var item: Dictionary = D6Loot.generate_item(g, {"slot": slot, "rarity": "rare"})
	g.room.interact = {"kind": "loot", "x": g.player.x, "y": g.player.y, "r": g.tuning.room.rewardRadius, "used": false, "item": item}
	D6Run.open_interact(g)
	return item

## Un marchand qui ne vend qu'un objet rare du type `slot`, son menu ouvert. Rend l'objet.
static func _open_shop(g: Dictionary, slot: String) -> Dictionary:
	var item: Dictionary = D6Loot.generate_item(g, {"slot": slot, "rarity": "rare"})
	g.run.gold = RICH
	g.room.interact = {"kind": "shop", "x": g.player.x, "y": g.player.y, "r": g.tuning.room.calmRadius, "used": false, "offers": [{"kind": "item", "price": PRICE, "label": item.name, "text": "", "item": item, "sold": false}]}
	D6Run.open_interact(g)
	return item

static func _t_butin_equipe(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": SEED})
	var old = g.meta.equipment.armure
	var old_uid = old.get("uid") if old is Dictionary else null
	var seq: float = g.meta.itemSeq
	var item := _open_loot(g, "armure")
	h.egal(g.mode, "choice", "le menu du butin est ouvert")
	h.ok(not item.has("uid"), "un butin au sol n'a pas encore d'identifiant")
	h.ok(D6Game.apply_command(g, {"type": "equip"}), "« équiper » accepté")
	h.ok(is_same(g.meta.equipment.armure, item) and is_same(g.run.items.armure, item), "l'objet équipé est dans le profil")
	h.ok(_has_uid(item), "l'objet équipé a reçu son identifiant en entrant dans le profil (uid : %s)" % str(item.get("uid")))
	h.ok(g.meta.itemSeq > seq, "le compteur d'identifiants du profil a avancé")
	h.ok(_uids_ok(g.meta), "tous les identifiants du profil sont posés et différents")
	if old is Dictionary:
		h.ok(g.meta.stash.any(func(it): return is_same(it, old)) and old.get("uid") == old_uid or old_uid == null, "l'ancienne armure est au coffre, avec son identifiant")

static func _t_achat_equipe(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": SEED})
	var item := _open_shop(g, "talisman")
	h.egal(g.mode, "choice", "le menu du marchand est ouvert")
	h.ok(D6Game.apply_command(g, {"type": "choose", "index": 0.0}), "l'achat est accepté")
	h.egal(g.run.gold, RICH - PRICE, "l'objet est payé")
	h.ok(is_same(g.meta.equipment.talisman, item), "l'objet acheté est porté")
	h.ok(_has_uid(item), "l'objet acheté a reçu son identifiant en entrant dans le profil (uid : %s)" % str(item.get("uid")))
	h.ok(_uids_ok(g.meta), "tous les identifiants du profil sont posés et différents")

## Le profil tenu en mémoire après une descente est celui que le jeu relirait du disque.
static func _t_profil_relu(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": SEED})
	for slot in ["armure", "talisman", "armure"]:
		_open_loot(g, slot)
		h.ok(D6Game.apply_command(g, {"type": "equip"}), "« équiper » accepté (%s)" % slot)
	_open_shop(g, "talisman")
	h.ok(D6Game.apply_command(g, {"type": "choose", "index": 0.0}), "l'achat est accepté")
	D6Run.sync_purse(g)
	var reread: Dictionary = D6Profile.sanitize_profile(D6Js.clone(g.meta), g.tuning)
	h.egal(reread, g.meta, "le profil relu est le profil en mémoire")

static func tests(h) -> void:
	h.test("défaut 19 · un butin équipé en donjon reçoit son identifiant en entrant dans le profil", func(): _t_butin_equipe(h))
	h.test("défaut 19 · un objet acheté au marchand et porté reçoit son identifiant en entrant dans le profil", func(): _t_achat_equipe(h))
	h.test("défaut 19 · après des objets équipés en donjon, le profil relu est le profil en mémoire", func(): _t_profil_relu(h))
