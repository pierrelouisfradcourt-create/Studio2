extends RefCounted
## Adaptateurs des vecteurs « profile » (src/sim/profile.mjs). Les opérations de la Ville
## modifient le profil : chaque cas part d'une copie du profil d'avant, et la sortie comparée
## porte le profil d'après.

const Outils := preload("res://parite/adaptateurs/state.gd")

## Opération (profil, tuning, …) -> { ok, reason? } ; arguments [profil avant, surcharge, …].
static func _op(f: Callable, a: Array) -> Dictionary:
	var p: Dictionary = D6Js.clone(a[0])
	var ret = f.callv([p, Outils.tuning(a[1])] + a.slice(2))
	return {"ret": ret, "profile": p}

static func _grant_class_starters(a: Array) -> Dictionary:
	var p: Dictionary = D6Js.clone(a[0])
	D6Profile.grant_class_starters(p, Outils.tuning(a[1]), a[2])
	return p

static func _ensure_uid(a: Array) -> Dictionary:
	var p: Dictionary = D6Js.clone(a[0])
	var it: Dictionary = D6Js.clone(a[1])
	var ret = D6Profile.ensure_uid(p, it)
	return {"ret": ret, "itemSeq": p.itemSeq, "item": it}

static func _fix_loadout(a: Array) -> Dictionary:
	var p: Dictionary = D6Js.clone(a[0])
	D6Profile.fix_loadout(p, Outils.tuning(a[1]))
	return p

static func _stash_loot(a: Array) -> Dictionary:
	var p: Dictionary = D6Js.clone(a[0])
	D6Profile.stash_loot(p, D6Js.clone(a[1]))
	return p

static func adapters() -> Dictionary:
	var ops := {
		"unlock": D6Profile.unlock,
		"buyUpgrade": D6Profile.buy_upgrade,
		"selectClass": D6Profile.select_class,
		"selectSkill": D6Profile.select_skill,
		"selectGadget": D6Profile.select_gadget,
		"equipFromStash": D6Profile.equip_from_stash,
		"salvageFromStash": D6Profile.salvage_from_stash,
	}
	var out := {}
	for k in ops:
		var f: Callable = ops[k]
		out[k] = func(a): return _op(f, a)
	out["createProfile"] = func(a): return D6Profile.create_profile(Outils.tuning(a[0]))
	out["newProfile"] = func(a): return D6Profile.new_profile(Outils.tuning(a[0]))
	out["grantClassStarters"] = _grant_class_starters
	out["isItem"] = func(a): return D6Profile.is_item(a[0])
	out["sanitizeProfile"] = func(a): return D6Profile.sanitize_profile(D6Js.clone(a[0]), Outils.tuning(a[1]))
	out["ensureUid"] = _ensure_uid
	out["fixLoadout"] = _fix_loadout
	out["unlockCost"] = func(a): return D6Profile.unlock_cost(Outils.tuning(a[0]), a[1], a[2])
	out["starterWeapon"] = func(a): return D6Profile.starter_weapon(Outils.tuning(a[0]), a[1])
	out["upgradeCost"] = func(a): return D6Profile.upgrade_cost(Outils.tuning(a[0]), a[1], a[2])
	out["salvageSouls"] = func(a): return D6Profile.salvage_souls(Outils.tuning(a[0]), a[1])
	out["stashLoot"] = _stash_loot
	return out
