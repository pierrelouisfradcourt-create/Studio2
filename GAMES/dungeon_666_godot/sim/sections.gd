class_name D6Sections
extends RefCounted
## Portage de src/sim/sections.mjs.
## PLAN DE SECTION — aucun des 666 étages n'est écrit à la main. Une section (18 étages) est
## décrite par une fonction PURE et déterministe de (tuning, graine, numéro de section), qui
## assemble des BRIQUES réutilisables :
##   - le RYTHME (tuning.section.rhythms) : l'emplacement de chaque index — combat court (1 vague),
##     normal (2) ou assaut (3), halte, antichambre du Gardien, Gardien ;
##   - les PORTES : imposées (halte, antichambre, Gardien) ou tirées (tuning.section.doorWeights ×
##     thème du Cercle), avec une épreuve d'élite et une chambre forte GARANTIES dans la section ;
##   - le COMBAT : vagues, budget de menace, dispositions permises (room.mjs), bestiaire pondéré
##     (ROSTER de room.mjs + archétypes ajoutés par foe_data.mjs) ;
##   - le THÈME du Cercle (tuning.circles) : pondérations du bestiaire par COÛT, jamais par nom
##     (un archétype ajouté entre dans le tirage sans être nommé), archétypes « vedettes » tirés
##     par section, dispositions et portes favorites ;
##   - le GARDIEN de la section (floors.guardianFor).
## Le run (run.mjs) COMPOSE ensuite chaque étage : plan de l'index + porte choisie (composeFloor).
##
## Graine : celle de la partie. Le plan a son propre flux (hashSeed) : le calculer ne consomme
## jamais les flux de la partie, et la même partie revoit le même plan après une mort.
##
## FLOOR_TYPE_OF_REWARD (type d'étage qu'ouvre chaque récompense de porte ; le reste : combat qui
## rend cette récompense) : D6Data.tables().sections. ROSTER, LAYOUT_IDS : D6Data.tables().room.

const PLAN_SALT := 0x5ec7

## Récompense d'une salle de combat (porte « boon », « loot », « gold », « heal »).
const COMBAT_REWARDS := ["boon", "loot", "gold", "heal"]

static func _neutral_theme() -> Dictionary:
	return {"id": "neutre", "costBias": 0.0, "featured": 0.0, "featuredMult": 1.0, "budgetMult": 1.0, "strayEliteMult": 1.0, "layouts": null, "doors": {}}

static func _floor_type_of_reward() -> Dictionary:
	return D6Data.tables().sections.FLOOR_TYPE_OF_REWARD

static func _roster() -> Array:
	return D6Data.tables().room.ROSTER

static func _layout_ids() -> Array:
	return D6Data.tables().room.LAYOUT_IDS

## [...new Set(arr)] : les valeurs dans l'ordre de leur 1re apparition.
static func _unique(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		if not out.has(v):
			out.append(v)
	return out

static func section_count(tuning: Dictionary) -> float:
	return ceilf(tuning.floors.total / tuning.floors.sectionLength)

## Thème du Cercle `circle` (1..10) : données de tuning.circles complétées par le thème neutre.
static func circle_theme(tuning: Dictionary, circle: float) -> Dictionary:
	var list = tuning.get("circles")
	if list == null:
		list = []
	var c = null
	if list.size() > 0:
		var i := minf(list.size(), maxf(1.0, circle)) - 1.0
		if i == floorf(i): # Cercle non entier : list[1.5] est « undefined » en JavaScript
			c = list[int(i)]
	var theme := _neutral_theme()
	if c is Dictionary:
		theme.merge(c, true)
	theme.circle = circle
	return theme

## Plan complet de la section `section` (1..37) : 18 entrées (index 1..18), chacune décrivant
## l'emplacement, le rythme, les portes qui y MÈNENT, et la composition d'un combat à cet index.
static func section_plan(tuning: Dictionary, seed, section: float) -> Dictionary:
	var sec: Dictionary = tuning.section
	var length: float = tuning.floors.sectionLength
	var s := maxf(1.0, minf(section_count(tuning), floorf(section)))
	var rng := D6Rng.create_rng(D6Rng.hash_seed(D6Js.u32(seed), [PLAN_SALT, s]))
	var bounds := D6Floors.section_bounds(tuning, s)
	var head := D6Floors.floor_info(tuning, bounds.first)
	var theme := circle_theme(tuning, head.circle)
	# Tirages du plan, toujours dans le même ordre (déterminisme).
	var rhythm_id := 0.0 if s == 1.0 or sec.rhythms.size() == 1 else floorf(D6Rng.rand(rng) * sec.rhythms.size())
	var rhythm: Array = sec.rhythms[int(rhythm_id)]
	var featured := _draw_featured(rng, tuning, theme)
	var fixed_halte: Array = D6Js.nz(sec.halte.get("fixed"), [])
	var halte_doors: Array = fixed_halte + _draw_distinct(rng, sec.halte.pool, sec.halte.doors - fixed_halte.size())
	var treasure_at = _draw_treasure_index(rng, sec, rhythm)
	var guardian = D6Floors.guardian_for(tuning, s)
	var door_weights := _door_weights_for(tuning, theme)
	var floors: Array = []
	for i in range(1, int(length) + 1):
		var index := float(i)
		var floor: float = bounds.first + index - 1.0
		var slot = "gardien" if index == length else rhythm[i - 1]
		floors.append(_plan_entry(tuning, {"s": s, "index": index, "floor": floor, "slot": slot, "theme": theme, "featured": featured, "halteDoors": halte_doors, "treasureAt": treasure_at, "guardian": guardian, "doorWeights": door_weights}))
	return {
		"section": s,
		"first": bounds.first,
		"guardianFloor": bounds.guardian,
		"checkpoint": bounds.checkpoint,
		"circle": head.circle,
		"circleName": head.circleName,
		"theme": {"id": theme.id, "circle": head.circle, "name": head.circleName, "costBias": theme.costBias, "featured": featured, "featuredMult": theme.featuredMult},
		"rhythmId": rhythm_id,
		"guardian": guardian,
		"treasureAt": treasure_at,
		"floors": floors,
	}

static func _plan_entry(tuning: Dictionary, ctx: Dictionary) -> Dictionary:
	var index: float = ctx.index
	var floor: float = ctx.floor
	var slot = ctx.slot
	var theme: Dictionary = ctx.theme
	var door_weights: Array = ctx.doorWeights
	var sec: Dictionary = tuning.section
	var enc: Dictionary = tuning.encounter
	var pace_name = slot if D6Js.truthy(sec.paces.get(slot)) else sec.calmPace
	var pace: Dictionary = sec.paces[pace_name]
	var doors = null
	if slot == "gardien":
		doors = ["boss"]
	elif slot == "halte":
		doors = ctx.halteDoors.duplicate()
	elif slot == "antichambre":
		doors = sec.antichambre.duplicate()
	var guarantee = null
	if doors == null and sec.eliteAt.has(index):
		guarantee = "elite"
	elif doors == null and ctx.treasureAt != null and index == ctx.treasureAt:
		guarantee = "treasure"
	var offers = doors
	if offers == null:
		offers = door_weights.filter(func(d): return d.weight > 0.0).map(func(d): return d.reward)
		if guarantee != null:
			offers.append(guarantee)
		offers = _unique(offers)
	var type_of := _floor_type_of_reward()
	var scale := D6Floors.floor_scaling(tuning, floor)
	return {
		"index": index,
		"floor": floor,
		"slot": slot, # court | normal | assaut | halte | antichambre | gardien
		"pace": pace_name, # rythme d'un combat joué à cet index
		"doors": doors, # portes IMPOSÉES qui mènent à cet étage (sinon tirées)
		"guarantee": guarantee, # récompense garantie parmi les portes tirées (élite, chambre forte)
		"doorWeights": null if doors != null else door_weights,
		"offers": offers, # récompenses possibles des portes qui mènent ici
		"types": _unique(offers.map(func(r): return D6Js.nz(type_of.get(r), "combat"))), # types d'étage possibles
		"waves": pace.waves,
		"budget": (enc.baseBudget + enc.perIndex * index) * pace.budgetMult * theme.budgetMult * scale.density,
		"layouts": _layouts_for(tuning, theme, floor),
		"roster": _roster_for(tuning, theme, ctx.featured, ctx.s, index),
		"strayEliteChance": enc.strayEliteChance * theme.strayEliteMult if floor >= enc.strayEliteFrom else 0.0,
		"guardian": ctx.guardian if slot == "gardien" else null,
	}

## Entrée du plan pour l'étage `floor` (1..666).
static func floor_slot(tuning: Dictionary, seed, floor) -> Dictionary:
	var info := D6Floors.floor_info(tuning, floor)
	return section_plan(tuning, seed, info.section).floors[int(info.indexInSection - 1.0)]

## COMPOSE l'étage `floor` à partir de son entrée de plan et de la porte qui y mène : c'est le
## plan de salle que buildRoom (room.mjs) et enterFloor (run.mjs) consomment. Fonction pure.
##   kind   : combat | elite | boss | shop | event | treasure | rest
##   reward : récompense de fin de salle (combat : celle de la porte ; élite : butin)
static func compose_floor(tuning: Dictionary, seed, floor, door = null) -> Dictionary:
	var info := D6Floors.floor_info(tuning, floor)
	var entry: Dictionary = section_plan(tuning, seed, info.section).floors[int(info.indexInSection - 1.0)]
	var has_door: bool = door is Dictionary
	var asked = "boss" if info.isBoss else (D6Js.nz(door.get("reward"), "boon") if has_door else "boon")
	var kind = D6Js.nz(_floor_type_of_reward().get(asked), "combat")
	var reward = kind
	if kind == "elite":
		reward = "loot"
	elif kind == "combat":
		reward = asked if COMBAT_REWARDS.has(asked) else "boon"
	return {
		"kind": kind,
		"reward": reward,
		"family": door.get("family") if has_door else null,
		"elite": kind == "elite",
		"floor": info.floor,
		"section": info.section,
		"index": entry.index,
		"slot": entry.slot,
		"pace": entry.pace,
		"waves": entry.waves,
		"budget": entry.budget,
		"layouts": entry.layouts,
		"roster": entry.roster,
		"strayEliteChance": entry.strayEliteChance,
		"guardian": D6Floors.guardian_for(tuning, info.section) if kind == "boss" else null,
		"theme": circle_theme(tuning, info.circle).id,
	}

# ---------------------------------------------------------------- briques du plan

## Dispositions permises à l'étage : le tout premier étage est ouvert (apprentissage).
static func _layouts_for(_tuning: Dictionary, theme: Dictionary, floor: float) -> Array:
	if floor == 1.0:
		return [{"id": "open", "weight": 1.0}]
	var ids := _layout_ids()
	var table = theme.get("layouts")
	if table == null:
		table = {}
		for id in ids:
			table[id] = 1.0
	var out: Array = []
	for id in table:
		var w = table[id]
		if ids.has(id) and w != null and w > 0.0:
			out.append({"id": id, "weight": w})
	return out

## Bestiaire pondéré de l'étage : dans la 1re section, les archétypes entrent progressivement
## (minIndex) ; ensuite tous sont là. Poids × (coût / costRef)^costBias × vedette.
static func _roster_for(tuning: Dictionary, theme: Dictionary, featured: Array, section: float, index: float) -> Array:
	var reach: float = tuning.floors.sectionLength if section > 1.0 else index
	var ref: float = tuning.encounter.costRef
	var out: Array = []
	for r in _roster():
		if r.minIndex <= reach and D6Js.truthy(tuning.enemies.get(r.kind)):
			var star: float = theme.featuredMult if featured.has(r.kind) else 1.0
			out.append({"kind": r.kind, "cost": r.cost, "weight": r.weight * D6Trig.pow(r.cost / ref, theme.costBias) * star})
	return out

## Archétypes vedettes de la section : tirés dans TOUT le bestiaire présent (aucun nom codé).
static func _draw_featured(rng: Dictionary, tuning: Dictionary, theme: Dictionary) -> Array:
	var kinds: Array = []
	for r in _roster():
		if D6Js.truthy(tuning.enemies.get(r.kind)) and not kinds.has(r.kind):
			kinds.append(r.kind)
	return D6Rng.shuffle(rng, kinds).slice(0, int(maxf(0.0, theme.featured)))

## Poids des portes tirées : base × multiplicateur du thème.
static func _door_weights_for(tuning: Dictionary, theme: Dictionary) -> Array:
	var doors = theme.get("doors")
	var weights: Dictionary = tuning.section.doorWeights
	var out: Array = []
	for reward in weights:
		var mult: float = D6Js.nz(doors.get(reward), 1.0) if doors is Dictionary else 1.0
		out.append({"reward": reward, "weight": weights[reward] * mult})
	return out

## `n` récompenses distinctes tirées dans un tableau de poids {récompense: poids}.
static func _draw_distinct(rng: Dictionary, pool: Dictionary, n: float) -> Array:
	var left: Array = []
	for reward in pool:
		if pool[reward] > 0.0:
			left.append({"reward": reward, "weight": pool[reward]})
	var out: Array = []
	while out.size() < n and left.size() > 0:
		var it = D6Rng.weighted_pick(rng, left, func(d): return d.weight)
		out.append(it.reward)
		for i in left.size():
			if is_same(left[i], it):
				left.remove_at(i)
				break
	return out

## Index où une porte de chambre forte est garantie : un combat tiré, hors élites imposées.
static func _draw_treasure_index(rng: Dictionary, sec: Dictionary, rhythm: Array):
	var from: float = sec.treasure.from
	var to: float = sec.treasure.to
	var candidates: Array = []
	var i := from
	while i <= to:
		var at := int(i) - 1
		var slot = rhythm[at] if at >= 0 and at < rhythm.size() and i == floorf(i) else null
		if D6Js.truthy(sec.paces.get(slot)) and not sec.eliteAt.has(i):
			candidates.append(i)
		i += 1.0
	if candidates.is_empty():
		return null
	return candidates[int(floorf(D6Rng.rand(rng) * candidates.size()))]
