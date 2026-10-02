class_name D6Loot
extends RefCounted
## Portage de src/sim/loot.mjs.
## Butin façon Diablo : raretés colorées, préfixes/suffixes, objets légendaires à pouvoir.
## Trois emplacements dans le prototype : arme, armure, talisman. L'équipement SURVIT à la
## mort (progression persistante) ; les bénédictions, elles, sont perdues.
##
## Tables ITEM_RARITIES (baseMult : multiplicateur de la valeur de base par rareté), SLOTS,
## SLOT_NAMES, BASES, AFFIXES ([stat, min, max, préfixe, suffixe, format] — valeurs de l'étage 1,
## mises à l'échelle ; format : 'pct', 'pctNeg', 'flat'), STAT_LABELS, LEGENDARY_POWERS :
## D6Data.tables().loot (jamais modifiées).

static func _t() -> Dictionary:
	return D6Data.tables().loot

static func _round_stat(v: float, format) -> float:
	return D6Js.jround(v) if format == "flat" else D6Js.jround(v * 1000.0) / 1000.0

## Rang d'une rareté dans ITEM_RARITIES (findIndex : -1 si inconnue).
static func _rarity_index(id) -> float:
	var rarities: Array = _t().ITEM_RARITIES
	for i in rarities.size():
		if rarities[i].id == id:
			return float(i)
	return -1.0

## item.base?.<key> : null si la base ou la clé manque.
static func _base_field(item: Dictionary, key: String):
	var base = item.get("base")
	return base.get(key) if base is Dictionary else null

## Tire une rareté ; `bonus` > 1 favorise les raretés hautes (élites, boss).
static func roll_rarity(game: Dictionary, bonus: float = 1.0) -> String:
	var w: Dictionary = game.tuning.loot.rarityWeights
	var r = D6Rng.weighted_pick(game.rng.gen, _t().ITEM_RARITIES, func(x): return w[x.id] if x.id == "commun" else w[x.id] * bonus)
	return r.id

## Type d'arme d'un objet trouvé : une arme que la classe jouée sait manier ET dont le type est
## débloqué en Ville. Une seule possibilité : aucun tirage (la graine reste stable).
static func _roll_weapon_type(game: Dictionary):
	var u = game.meta.get("unlocked")
	var unlocked = u.get("weapons") if u is Dictionary else null
	if unlocked == null:
		unlocked = []
	var pool: Array = D6Loadout.class_of(game).weapons.filter(func(w): return unlocked.has(w) and D6Js.truthy(game.tuning.weapons.get(w)))
	if pool.size() == 0:
		return D6Loadout.weapon_type_of(game)
	return pool[0] if pool.size() == 1 else D6Rng.pick(game.rng.gen, pool)

## `opts` tient les options nommées du JavaScript ({ slot, rarity, floor, weaponType }) :
## une clé absente ou nulle est tirée ou déduite.
static func generate_item(game: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var t := _t()
	var s = opts.get("slot")
	if s == null:
		s = D6Rng.pick(game.rng.gen, t.SLOTS)
	var wt = null
	if s == "arme":
		wt = opts.get("weaponType")
		if wt == null:
			wt = _roll_weapon_type(game)
	var rar = opts.get("rarity")
	if rar == null:
		rar = roll_rarity(game)
	var rdef: Dictionary = t.ITEM_RARITIES[int(_rarity_index(rar))]
	var lvl: float = D6Js.nz(opts.get("floor"), game.run.floor)
	var affixes := _roll_affixes(game, s, rdef, lvl)
	var has_wt: bool = D6Js.truthy(wt)
	var bases: Array = D6Js.nz(game.tuning.weapons[wt].get("bases"), t.BASES.arme) if has_wt else t.BASES[s]
	var base: String = D6Rng.pick(game.rng.gen, bases)
	var name := base
	if affixes.size() > 0:
		name = "%s %s" % [base, affixes[0].prefix]
	if affixes.size() > 1:
		name = "%s %s" % [name, affixes[1].suffix]
	var power = null
	if rar == "legendaire":
		var pw: Dictionary = D6Rng.pick(game.rng.gen, t.LEGENDARY_POWERS)
		power = pw.id
		name = "%s %s" % [base, pw.name]
	var weapon_mult: float = D6Js.nz(game.tuning.weapons[wt].get("baseMult"), 1.0) if has_wt else 1.0
	var item := {"id": D6State.new_id(game), "slot": s, "rarity": rar, "name": name, "level": lvl, "affixes": affixes, "power": power, "base": _base_values(game, s, lvl, rdef.baseMult * weapon_mult)}
	if has_wt:
		item.weaponType = wt
	item.score = item_score(item)
	return item

## Affixes de l'objet : le bassin de l'emplacement est mélangé, puis chaque affixe retenu tire
## sa valeur (même ordre de tirages que le JavaScript).
static func _roll_affixes(game: Dictionary, slot, rdef: Dictionary, lvl: float) -> Array:
	var scale: float = 1.0 + game.tuning.loot.affixFloorScale * (lvl - 1.0)
	var pool: Array = D6Rng.shuffle(game.rng.gen, _t().AFFIXES[slot].duplicate())
	var affixes: Array = []
	for a in pool.slice(0, int(rdef.affixes)):
		var lo: float = a[1]
		var hi: float = a[2]
		var format = a[5]
		var raw := lo + D6Rng.rand(game.rng.gen) * (hi - lo)
		var value := _round_stat(raw * scale if format == "flat" else raw * sqrt(scale), format)
		affixes.append({"stat": a[0], "value": value, "prefix": a[3], "suffix": a[4], "format": format})
	return affixes

static func _base_values(game: Dictionary, slot, level: float, mult: float) -> Dictionary:
	# Même pente que le niveau d'objet du scaling (floors.itemGrowth) : l'équipement suit la descente.
	var growth: float = 1.0 + game.tuning.floors.itemGrowth * (level - 1.0)
	if slot == "arme":
		return {"damage": D6Js.jround(game.tuning.weaponBase * growth * mult * 10.0) / 10.0}
	if slot == "armure":
		return {"hp": D6Js.jround(game.tuning.armorBase * growth * mult)}
	return {}

## Équipement de départ : arme (celle de la classe) et armure communes, sans affixe.
static func starter_items(game: Dictionary) -> Dictionary:
	var wt = D6Loadout.class_of(game).weapons[0]
	var w: Dictionary = game.tuning.weapons[wt]
	return {
		"arme": {"id": D6State.new_id(game), "slot": "arme", "weaponType": wt, "rarity": "commun", "name": D6Js.nz(w.get("starterName"), w.get("name")), "level": 1.0, "affixes": [], "power": null, "base": {"damage": game.tuning.weaponBase * D6Js.nz(w.get("baseMult"), 1.0)}, "score": 0.0},
		"armure": {"id": D6State.new_id(game), "slot": "armure", "rarity": "commun", "name": "Haillons de pèlerin", "level": 1.0, "affixes": [], "power": null, "base": {"hp": game.tuning.armorBase}, "score": 0.0},
		"talisman": null,
	}

## Score grossier de puissance (comparaison « mieux / moins bien » dans l'interface).
static func item_score(item: Dictionary) -> float:
	var s := 0.0
	var damage = _base_field(item, "damage")
	if D6Js.truthy(damage):
		s += damage / 2.0
	var hp = _base_field(item, "hp")
	if D6Js.truthy(hp):
		s += hp / 12.0
	for a in item.affixes:
		s += a.value / 25.0 if a.format == "flat" else absf(a.value) * 8.0
	if D6Js.truthy(item.get("power")):
		s += 2.0
	return D6Js.jround(s * 100.0) / 100.0

## Or rendu par un objet recyclé en donjon (economy.salvage) : une base, plus un montant par rang
## de rareté, plus 1 or tous les `levelsPerGold` niveaux d'objet.
static func salvage_value(game: Dictionary, item: Dictionary) -> float:
	var s: Dictionary = game.tuning.economy.salvage
	var idx := _rarity_index(item.get("rarity"))
	return s.base + idx * s.perRarity + floorf(item.level / s.levelsPerGold)

static func base_text(item: Dictionary):
	var damage = _base_field(item, "damage")
	if D6Js.truthy(damage):
		return "Dégâts de l'arme : %s" % D6Js.num_str(damage)
	var hp = _base_field(item, "hp")
	if D6Js.truthy(hp):
		return "PV de l'armure : %s" % D6Js.num_str(hp)
	return null

static func affix_text(a: Dictionary) -> String:
	var label = D6Js.nz(_t().STAT_LABELS.get(a.stat), a.stat)
	if a.format == "flat":
		return "+%s %s" % [D6Js.num_str(a.value), label]
	if a.format == "pctNeg":
		return "%s %% %s" % [D6Js.num_str(D6Js.jround(a.value * 100.0)), label]
	return "+%s %% %s" % [D6Js.num_str(D6Js.jround(a.value * 1000.0) / 10.0), label]

static func random_shop_item(game: Dictionary) -> Dictionary:
	var rarity := "rare" if D6Rng.rand(game.rng.gen) < game.tuning.economy.shopRareChance else "magique"
	return generate_item(game, {"rarity": rarity})

static func price_of(game: Dictionary, item: Dictionary) -> float:
	var lo: float = game.tuning.economy.shopItemPrice[0]
	var hi: float = game.tuning.economy.shopItemPrice[1]
	var idx := _rarity_index(item.get("rarity"))
	return D6Js.jround(lo + ((hi - lo) * idx) / (_t().ITEM_RARITIES.size() - 1.0)) + D6Rng.rand_int(game.rng.gen, 0.0, game.tuning.economy.shopPriceJitter)
