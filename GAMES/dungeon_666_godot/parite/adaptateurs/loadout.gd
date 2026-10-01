extends RefCounted
## Adaptateurs des vecteurs « loadout » (src/sim/loadout.mjs). Argument : une fiche de partie.

const Outils := preload("res://parite/adaptateurs/state.gd")

static func _resolve_kit(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	var ret := D6Loadout.resolve_kit(g)
	var t: Dictionary = g.tuning
	return {
		"kit": g.kit,
		"retIsKit": is_same(ret, g.kit),
		"weapon": t.weapon.name,
		"comboSame": is_same(t.combo, t.weapons[g.kit.weaponType].combo),
		"dashStrikeSame": is_same(t.dashStrike, t.weapons[g.kit.weaponType].dashStrike),
		"skillSame": is_same(t.skill, t.skills[g.kit.skillId]),
		"gadgetSame": is_same(t.gadget, t.gadgets[g.kit.gadgetId]),
		"skill": t.skill.name,
		"gadget": t.gadget.name,
		"super": t["super"].name,
	}

static func adapters() -> Dictionary:
	return {
		"classOf": func(a): return D6Loadout.class_of(Outils.make_game(a[0])).name,
		"classIdOf": func(a): return D6Loadout.class_id_of(Outils.make_game(a[0])),
		"weaponTypeOf": func(a): return D6Loadout.weapon_type_of(Outils.make_game(a[0])),
		"resolveKit": _resolve_kit,
	}
