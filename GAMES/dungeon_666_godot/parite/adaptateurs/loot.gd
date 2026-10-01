extends RefCounted
## Adaptateurs des vecteurs « loot » (src/sim/loot.mjs). Une partie est désignée par sa fiche ;
## les sorties des fonctions à tirage portent l'état du flux (`s`) et le prochain identifiant.

const Outils := preload("res://parite/adaptateurs/state.gd")

static func _roll_rarity(a: Array) -> Array:
	var g := Outils.make_game(a[0])
	var out: Array = []
	for i in 8:
		out.append(D6Loot.roll_rarity(g) if a[1] == null else D6Loot.roll_rarity(g, a[1]))
	return out

static func _generate_item(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	var item := D6Loot.generate_item(g) if a[1] == null else D6Loot.generate_item(g, D6Js.clone(a[1]))
	return {"item": item, "s": g.rng.gen.s, "nextId": g.nextId}

static func _starter_items(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	return {"items": D6Loot.starter_items(g), "nextId": g.nextId}

static func _random_shop_item(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	var item := D6Loot.random_shop_item(g)
	return {"item": item, "s": g.rng.gen.s, "nextId": g.nextId}

static func _price_of(a: Array) -> Dictionary:
	var g := Outils.make_game(a[0])
	return {"price": D6Loot.price_of(g, a[1]), "s": g.rng.gen.s}

static func adapters() -> Dictionary:
	return {
		"rollRarity": _roll_rarity,
		"generateItem": _generate_item,
		"starterItems": _starter_items,
		"itemScore": func(a): return D6Loot.item_score(a[0]),
		"salvageValue": func(a): return D6Loot.salvage_value(a[0]),
		"baseText": func(a): return D6Loot.base_text(a[0]),
		"affixText": func(a): return D6Loot.affix_text(a[0]),
		"randomShopItem": _random_shop_item,
		"priceOf": _price_of,
	}
