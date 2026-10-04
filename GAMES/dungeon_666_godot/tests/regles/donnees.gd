extends RefCounted
## Les DONNÉES du jeu (data/*.json) se répondent-elles ?
##
## Le validateur du kit (data/validation.json + data/schemas/) juge chaque fichier seul : types,
## bornes, champs obligatoires. Ici, ce qu'un schéma ne sait pas dire — les RÉFÉRENCES CROISÉES
## entre fichiers (l'arme d'une classe existe, chaque ennemi d'une vague a ses données, chaque
## disposition citée par un Cercle est dessinée…) et les règles qui lient deux nombres (un
## télégraphe de Gardien n'est jamais plus court que GUARDIAN_MIN_TELE).
## Chaque test nomme la donnée fautive : c'est ce message qu'on lit après avoir réglé un nombre.

const MIN_TELEGRAPH := 0.4 # s : pilier du jeu — tout coup ennemi s'annonce au moins aussi longtemps
const ENEMY_TELEGRAPHS := ["windup", "castTime", "channel", "slashWindup"] # et pyre.delay
const ELITE_TELEGRAPHS := ["deathBlastDelay", "warn", "channel"]
const BOSS_TELEGRAPHS := ["windup", "secondWindup", "delay", "delayMin", "leapDelay"]
const AFFIX_FORMATS := ["pct", "flat", "pctNeg"]
const STARTER := {"weapons": "lame", "skills": "lance", "gadgets": "nova", "supers": "colere"} # D6Data.create_tuning
const ROOM_SLACK := 1.0 # u : marge d'arrondi d'un obstacle contre le bord de la salle
## Champs qu'un effet d'autel lit dans son option (sim/run.gd, _apply_event et _option_blocked).
const ALTAR_FIELDS := {
	"none": [], "bloodBoon": ["pct", "rarity"], "heal": ["pct"], "gadgetCharge": ["gain"],
	"cursedChest": ["hp", "rarity"], "mammonBoon": ["cost", "family"], "gold": ["gain"],
	"soulBoon": ["souls", "rarity"], "bloodSouls": ["hp", "gain"], "reforge": ["levels"], "pact": ["pact"],
	"superToHp": ["need", "pct"], "hpToSuper": ["hp"],
}
const ALTAR_ITEM_EFFECTS := ["cursedChest"] # leur « rarity » est une rareté d'OBJET ; ailleurs, de bénédiction
## Réglages que l'IA d'un archétype d'origine lit sans repli (sim/enemies.gd) : absents, l'ennemi plante.
const BASE_AI_FIELDS := {
	"imp": ["attackRange", "circleDist", "circleWithin", "flankSpeed", "windup", "lockAt", "strikeTime", "strikeSpeed", "recover", "cooldown"],
	"archer": ["preferredDist", "fleeDist", "approachSlack", "fireRangeFrac", "strafeMult", "strafeFlip", "windup", "lockAt", "recover", "cooldown", "projSpeed", "projRadius", "projRange", "teleLength"],
	"brute": ["attackRange", "triggerFrac", "windup", "slamRadius", "recover", "cooldown"],
	"charger": ["attackRange", "windup", "lockAt", "chargeSpeed", "chargeMaxTime", "wallStun", "recover", "cooldown"],
	"exploder": ["triggerRange", "windup", "blastRadius"],
}

static func _t() -> Dictionary:
	return D6Data.default_tuning()

static func _tb() -> Dictionary:
	return D6Data.tables()

static func _ids(list: Array, key: String = "id") -> Array:
	return list.map(func(x): return x[key])

## Tous les éléments de `wanted` sont dans `known` ; sinon le test nomme le premier absent.
static func _all_in(h, wanted: Array, known: Array, what: String) -> void:
	for id in wanted:
		h.ok(known.has(id), "%s : « %s » n'existe pas (connus : %s)" % [what, str(id), ", ".join(known.map(func(k): return str(k)))])
	h.ok(true)

static func _same_set(h, a: Array, b: Array, what: String) -> void:
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	h.egal(x, y, what)

# ---------------------------------------------------------------- classes et kits

static func _classes(h) -> void:
	var t := _t()
	for class_id in t.classes:
		var c: Dictionary = t.classes[class_id]
		_all_in(h, c.weapons, t.weapons.keys(), "classe %s, arme" % class_id)
		_all_in(h, c.skills, t.skills.keys(), "classe %s, compétence" % class_id)
		_all_in(h, c.gadgets, t.gadgets.keys(), "classe %s, gadget" % class_id)
		_all_in(h, [c["super"]], t.supers.keys(), "classe %s, Super" % class_id)
		for w in c.weapons:
			if t.weapons.has(w):
				h.egal(t.weapons[w].className, class_id, "arme %s : className" % w)

static func _kit_orphans(h) -> void:
	var t := _t()
	var used := {"weapons": [], "skills": [], "gadgets": [], "supers": []}
	for class_id in t.classes:
		var c: Dictionary = t.classes[class_id]
		used.weapons.append_array(c.weapons)
		used.skills.append_array(c.skills)
		used.gadgets.append_array(c.gadgets)
		used.supers.append(c["super"])
	for family in used:
		_all_in(h, t[family].keys(), used[family], "%s : aucune classe ne l'a" % family)
	for w in t.weapons:
		_all_in(h, [t.weapons[w].className], t.classes.keys(), "arme %s, classe" % w)

static func _starter(h) -> void:
	var t := _t()
	for family in STARTER:
		_all_in(h, [STARTER[family]], t[family].keys(), "kit de départ, %s" % family)
	var d: Dictionary = _tb().kits.DEFAULT_LOADOUT
	_all_in(h, [d.classId], t.classes.keys(), "DEFAULT_LOADOUT.classId")
	var c: Dictionary = t.classes.get(d.classId, {"skills": [], "gadgets": []})
	# Combat V3 : trois emplacements, chacun une compétence ou un gadget de la classe, ou null.
	h.egal(d.slots.size(), D6Loadout.SLOTS, "DEFAULT_LOADOUT.slots : trois emplacements")
	var places: Array = d.slots.filter(func(id): return id != null)
	_all_in(h, places, c.skills + c.gadgets, "DEFAULT_LOADOUT.slots (compétences et gadgets de %s)" % d.classId)
	for id in places:
		h.egal(places.count(id), 1, "DEFAULT_LOADOUT.slots : %s placé une seule fois" % id)
	h.egal(D6Profile.create_profile(t).loadout, d, "un profil neuf porte DEFAULT_LOADOUT")

static func _combo_cancel(h) -> void:
	var t := _t()
	for w in t.weapons:
		var combo: Array = t.weapons[w].combo
		for i in combo.size():
			h.ok(combo[i].has("cancelFrom") or i < t.comboCancelFrom.hits.size(), "arme %s, coup %d : ni cancelFrom ni comboCancelFrom.hits[%d]" % [w, i + 1, i])
			h.egal(combo[i].has("shot"), t.weapons[w].kind == "ranged", "arme %s (%s), coup %d : « shot » réservé aux armes à distance" % [w, t.weapons[w].kind, i + 1])

# ---------------------------------------------------------------- bestiaire

static func _roster(h) -> void:
	var t := _t()
	var roster: Array = _tb().room.ROSTER
	_all_in(h, _ids(roster, "kind"), t.enemies.keys(), "ROSTER, kind")
	_all_in(h, t.enemies.keys(), _ids(roster, "kind"), "ennemi absent du ROSTER")
	for r in roster:
		h.ok(r.minIndex <= t.floors.sectionLength, "ROSTER %s : minIndex %s au-delà de la section (%s étages)" % [r.kind, str(r.minIndex), str(t.floors.sectionLength)])
	h.ok(roster.any(func(r): return r.minIndex <= 1.0), "ROSTER : aucun ennemi disponible au premier étage")

static func _kind_lists(h) -> void:
	var t := _t()
	var kinds: Array = t.enemies.keys()
	_all_in(h, _tb().ai_common.MELEE_KINDS, kinds, "MELEE_KINDS")
	_all_in(h, _tb().ai_common.SHOOTER_KINDS, kinds, "SHOOTER_KINDS")
	_all_in(h, _tb().foe_data.EXTRA_ELITE_KINDS, kinds, "EXTRA_ELITE_KINDS")
	for kind in t.enemies:
		if t.enemies[kind].has("minionKind"):
			_all_in(h, [t.enemies[kind].minionKind], kinds, "%s.minionKind" % kind)
	for mod in t.elite.mods:
		var m: Dictionary = t.elite.mods[mod]
		_all_in(h, m.get("excludeKinds", []), kinds, "elite.mods.%s.excludeKinds" % mod)
		if m.has("kind"):
			_all_in(h, [m.kind], kinds, "elite.mods.%s.kind" % mod)

static func _enemy_telegraphs(h) -> void:
	var t := _t()
	var slowest: float = 1.0
	for mod in t.elite.mods:
		slowest = minf(slowest, t.elite.mods[mod].get("windupMult", 1.0))
		for key in ELITE_TELEGRAPHS:
			if t.elite.mods[mod].has(key):
				h.ok(t.elite.mods[mod][key] >= MIN_TELEGRAPH, "elite.mods.%s.%s : %s s < %s s" % [mod, key, str(t.elite.mods[mod][key]), str(MIN_TELEGRAPH)])
	for kind in t.enemies:
		var e: Dictionary = t.enemies[kind]
		var found: Array = []
		for key in ENEMY_TELEGRAPHS:
			if e.has(key):
				found.append(e[key])
				h.ok(e[key] * slowest >= MIN_TELEGRAPH, "%s.%s : télégraphe de %s s (× %s chez un champion) < %s s" % [kind, key, str(e[key]), str(slowest), str(MIN_TELEGRAPH)])
		if e.has("pyre"):
			found.append(e.pyre.delay)
			h.ok(e.pyre.delay >= MIN_TELEGRAPH, "%s.pyre.delay : %s s < %s s" % [kind, str(e.pyre.delay), str(MIN_TELEGRAPH)])
		h.ok(e.damage == 0.0 or not found.is_empty(), "%s : inflige %s dégâts sans aucun télégraphe (%s, pyre.delay)" % [kind, str(e.damage), ", ".join(ENEMY_TELEGRAPHS)])

# ---------------------------------------------------------------- Gardiens

static func _guardians(h) -> void:
	var t := _t()
	_all_in(h, t.guardians.rotation, t.boss.keys(), "guardians.rotation")
	_all_in(h, t.boss.keys(), t.guardians.rotation, "Gardien hors de la rotation")
	for id in t.boss:
		var b: Dictionary = t.boss[id]
		h.ok(b.phase3At < b.phase2At, "%s : phase3At (%s) doit être sous phase2At (%s)" % [id, str(b.phase3At), str(b.phase2At)])
		for phase in b.reinforcements:
			_all_in(h, b.reinforcements[phase], t.enemies.keys(), "%s.reinforcements.%s" % [id, phase])
		for key in b:
			if b[key] is Dictionary and b[key].has("kind"):
				_all_in(h, [b[key].kind], t.enemies.keys(), "%s.%s.kind" % [id, key])

static func _guardian_telegraphs(h) -> void:
	var t := _t()
	var floor_tele: float = _tb().boss_data.GUARDIAN_MIN_TELE
	h.ok(floor_tele >= MIN_TELEGRAPH, "GUARDIAN_MIN_TELE (%s s) sous le télégraphe minimal du jeu (%s s)" % [str(floor_tele), str(MIN_TELEGRAPH)])
	var seen := 0
	for id in t.boss:
		var b: Dictionary = t.boss[id]
		if b.has("secondChargeWindup"):
			h.ok(b.secondChargeWindup >= floor_tele, "%s.secondChargeWindup : %s s < GUARDIAN_MIN_TELE (%s s)" % [id, str(b.secondChargeWindup), str(floor_tele)])
		for attack in b:
			if not (b[attack] is Dictionary):
				continue
			for key in BOSS_TELEGRAPHS:
				if b[attack].has(key):
					seen += 1
					h.ok(b[attack][key] >= floor_tele, "%s.%s.%s : %s s < GUARDIAN_MIN_TELE (%s s)" % [id, attack, key, str(b[attack][key]), str(floor_tele)])
	h.ok(seen >= t.boss.size() * 3, "trop peu de télégraphes de Gardien trouvés (%d) : les clés ont-elles changé de nom ?" % seen)

# ---------------------------------------------------------------- salles, Cercles, étages

static func _layouts(h) -> void:
	var t := _t()
	var layouts: Dictionary = _tb().room.LAYOUTS
	_all_in(h, _tb().room.COMBAT_LAYOUTS, layouts.keys(), "COMBAT_LAYOUTS")
	var cited: Array = _tb().room.COMBAT_LAYOUTS.duplicate()
	for c in t.circles:
		_all_in(h, c.layouts.keys(), layouts.keys(), "Cercle %s, disposition" % c.id)
		cited.append_array(c.layouts.keys())
		h.ok(c.layouts.values().any(func(w): return w > 0.0), "Cercle %s : aucune disposition de poids > 0" % c.id)
	_all_in(h, layouts.keys(), cited, "disposition qu'aucun Cercle ne tire")

static func _obstacles(h) -> void:
	var room: Dictionary = _t().room
	var all: Dictionary = _tb().room.LAYOUTS.duplicate()
	all["BOSS_LAYOUT"] = _tb().room.BOSS_LAYOUT
	for id in all:
		for o in all[id]:
			var x0: float = o[0] * room.width - o[2] / 2.0
			var y0: float = o[1] * room.height - o[3] / 2.0
			var inside: bool = x0 >= -ROOM_SLACK and y0 >= -ROOM_SLACK and x0 + o[2] <= room.width + ROOM_SLACK and y0 + o[3] <= room.height + ROOM_SLACK
			h.ok(inside, "disposition %s : l'obstacle %s sort de la salle (%s × %s)" % [id, str(o), str(room.width), str(room.height)])
	h.ok(true)

static func _circles(h) -> void:
	var t := _t()
	var f: Dictionary = t.floors
	h.egal(float(t.circles.size()), f.circleNames.size() + 1.0, "un Cercle par nom de circleNames, plus la finale")
	h.egal(fmod(f.circleLength, f.sectionLength), 0.0, "circleLength est un nombre entier de sections")
	h.ok(f.total > f.circleLength * f.circleNames.size(), "floors.total (%s) ne dépasse pas les Cercles nommés : la finale n'a pas d'étage" % str(f.total))
	for c in t.circles:
		_all_in(h, c.doors.keys(), t.section.doorWeights.keys(), "Cercle %s, porte" % c.id)

static func _section(h) -> void:
	var t := _t()
	var s: Dictionary = t.section
	for i in s.rhythms.size():
		var rhythm: Array = s.rhythms[i]
		h.egal(float(rhythm.size()), t.floors.sectionLength, "rhythms[%d] : un rythme par étage de la section" % i)
		h.egal(rhythm[-1], "gardien", "rhythms[%d] : la section finit par son Gardien" % i)
		h.egal(rhythm.count("gardien"), 1, "rhythms[%d] : un seul Gardien" % i)
		for pace in rhythm:
			h.ok(s.paces.has(pace) or pace in ["halte", "antichambre", "gardien"], "rhythms[%d] : rythme « %s » sans entrée dans paces" % [i, pace])
	_all_in(h, [s.calmPace], s.paces.keys(), "calmPace")
	for at in s.eliteAt:
		h.ok(at <= t.floors.sectionLength, "eliteAt %s au-delà de la section" % str(at))
	h.ok(s.treasure.from <= s.treasure.to and s.treasure.to <= t.floors.sectionLength, "treasure : from <= to <= sectionLength")

static func _rewards(h) -> void:
	var s: Dictionary = _t().section
	var labels: Array = _tb().run.REWARD_LABELS.keys()
	_all_in(h, s.doorWeights.keys(), labels, "doorWeights : récompense sans libellé (REWARD_LABELS)")
	_all_in(h, s.halte.fixed + s.halte.pool.keys() + s.antichambre, labels, "halte / antichambre : récompense sans libellé")
	_all_in(h, _tb().sections.FLOOR_TYPE_OF_REWARD.keys(), labels, "FLOOR_TYPE_OF_REWARD : récompense sans libellé")
	h.ok(s.halte.doors <= s.halte.fixed.size() + s.halte.pool.size(), "halte : plus de portes (%s) que de récompenses possibles" % str(s.halte.doors))

# ---------------------------------------------------------------- bénédictions, butin, Ville, labo

static func _boons(h) -> void:
	var b: Dictionary = _tb().boons
	var families: Array = b.FAMILIES.keys()
	for boon in b.BOONS + b.PACTS:
		_all_in(h, [boon.family], families, "bénédiction %s, famille" % boon.id)
	for duo in b.DUOS:
		_all_in(h, duo.families, families, "duo %s, famille" % duo.id)
		h.ok(duo.families[0] != duo.families[1], "duo %s : deux fois la même famille" % duo.id)
	var ids: Array = _ids(b.BOONS + b.DUOS + b.PACTS)
	for id in ids:
		h.egal(ids.count(id), 1, "identifiant de bénédiction « %s » en double (BOONS, DUOS, PACTS confondus)" % id)
	for family in families:
		h.ok(b.BOONS.any(func(x): return x.family == family), "famille %s : aucune bénédiction" % family)

static func _altars(h) -> void:
	var pacts: Array = _ids(_tb().boons.PACTS)
	var ids: Array = _ids(_tb().run.EVENTS)
	for ev in _tb().run.EVENTS:
		h.egal(ids.count(ev.id), 1, "autel « %s » en double" % ev.id)
		for o in ev.options:
			h.egal(o.has("pact"), o.effect == "pact", "autel %s : « pact » va avec l'effet pact" % ev.id)
			if o.has("pact"):
				_all_in(h, [o.pact], pacts, "autel %s, pacte" % ev.id)

static func _loot(h) -> void:
	var t := _t()
	var l: Dictionary = _tb().loot
	var rarities: Array = _ids(l.ITEM_RARITIES)
	_same_set(h, t.loot.rarityWeights.keys(), rarities, "loot.rarityWeights : une entrée par rareté d'objet")
	_same_set(h, t.town.salvageSouls.keys(), rarities, "town.salvageSouls : une entrée par rareté d'objet")
	_all_in(h, [t.economy.treasure.minRarity], rarities, "economy.treasure.minRarity")
	for table in ["SLOT_NAMES", "BASES", "AFFIXES"]:
		_same_set(h, l[table].keys(), l.SLOTS, "%s : une entrée par emplacement (SLOTS)" % table)
	_same_set(h, _tb().profile.EQUIP_SLOTS, l.SLOTS, "EQUIP_SLOTS")
	var most: float = 0.0
	for r in l.ITEM_RARITIES:
		most = maxf(most, r.affixes)
	for slot in l.AFFIXES:
		h.ok(l.AFFIXES[slot].size() >= most, "AFFIXES.%s : %d affixes pour une rareté qui en tire %s" % [slot, l.AFFIXES[slot].size(), str(most)])
		for a in l.AFFIXES[slot]:
			var good: bool = a[0] is String and a[1] is float and a[2] is float and a[3] is String and a[4] is String and AFFIX_FORMATS.has(a[5])
			h.ok(good, "AFFIXES.%s %s : attendu [stat, minimum, maximum, préfixe, suffixe, %s]" % [slot, str(a), " | ".join(AFFIX_FORMATS)])
			if good:
				h.ok(a[1] <= a[2], "AFFIXES.%s %s : minimum > maximum" % [slot, a[0]])
				h.ok(l.STAT_LABELS.has(a[0]), "AFFIXES.%s : stat « %s » sans libellé (STAT_LABELS)" % [slot, a[0]])

static func _town(h) -> void:
	var up: Dictionary = _t().town.upgrades
	for id in up:
		h.egal(float(up[id].costs.size()), up[id].max, "amélioration %s : un coût par niveau (max)" % id)
	h.ok(_tb().profile.STASH_MAX >= 1.0)

static func _resolve(root: Dictionary, path: String):
	var cur = root
	for part in path.split("."):
		if not (cur is Dictionary) or not cur.has(part):
			return null
		cur = cur[part]
	return cur

static func _lab(h) -> void:
	var t := _t()
	var axes: Dictionary = _tb().lab.LAB_AXES
	_same_set(h, t.lab.keys(), axes.keys(), "lab : une variante active par axe de LAB_AXES")
	for axis in axes:
		var a: Dictionary = axes[axis]
		_all_in(h, [a.reference, t.lab.get(axis)], a.options.keys(), "labo %s, variante" % axis)
		h.egal(t.lab.get(axis), a.reference, "labo %s : la variante active par défaut est la référence" % axis)
		for option in a.options:
			for path in a.options[option].set:
				var current = _resolve(t, path)
				h.ok(current != null, "labo %s.%s : le réglage « %s » n'existe pas" % [axis, option, path])
				if option == a.reference:
					h.egal(a.options[option].set[path], current, "labo %s : la référence décrit le réglage par défaut (%s)" % [axis, path])

# ---------------------------------------------------------------- un seul exemplaire de chaque nombre

static func _recomposed(h) -> void:
	var t := _t()
	var tb := _tb()
	h.egal(tb.kits.CLASSES, t.classes)
	h.egal(tb.kits.WEAPONS, t.weapons)
	h.egal(tb.kits.SKILLS, t.skills)
	h.egal(tb.kits.GADGETS, t.gadgets)
	h.egal(tb.kits.SUPERS, t.supers)
	h.egal(tb.town_data.UPGRADES, t.town.upgrades)
	h.egal(tb.boss_data.GUARDIAN_ROTATION, t.guardians.rotation)
	h.egal(tb.room.LAYOUT_IDS, tb.room.LAYOUTS.keys())
	h.egal(t.combo, t.weapons.lame.combo, "réglage actif par défaut : le combo de la Lame")
	h.ok(not t.has("skill") and not t.has("gadget"), "combat V3 : compétence et gadget se lisent par emplacement, plus de bloc actif")
	h.egal(tb.config.DT, D6Data.DT)
	h.ok(not is_same(tb.kits.WEAPONS, t.weapons), "tables et réglages sont des copies distinctes")
	for kind in tb.foe_data.EXTRA_ENEMIES:
		h.ok(not D6Data.BASE_KINDS.has(kind) and t.enemies.has(kind))

## Chaque effet d'autel trouve dans son option les champs qu'il lit ; raretés et familles existent.
static func _altar_fields(h) -> void:
	var boons: Dictionary = _tb().boons
	for ev in _tb().run.EVENTS:
		for o in ev.options:
			h.ok(ALTAR_FIELDS.has(o.effect), "autel %s : effet « %s » inconnu de sim/run.gd" % [ev.id, o.effect])
			for field in ALTAR_FIELDS.get(o.effect, []):
				h.ok(o.has(field), "autel %s, effet %s : le champ « %s » manque" % [ev.id, o.effect, field])
			if o.has("rarity"):
				var known: Array = _ids(_tb().loot.ITEM_RARITIES if ALTAR_ITEM_EFFECTS.has(o.effect) else boons.RARITIES)
				_all_in(h, [o.rarity], known, "autel %s, effet %s, rareté" % [ev.id, o.effect])
			if o.has("family"):
				_all_in(h, [o.family], boons.FAMILIES.keys(), "autel %s, famille" % ev.id)

## Un nombre d'option que le libellé ne reprend pas serait un nombre que le joueur ne voit pas — et
## un nombre écrit en dur dans le libellé pourrait mentir : tout chiffre d'un libellé vient d'un {champ}.
static func _altar_labels(h) -> void:
	var digits := RegEx.create_from_string("[0-9]")
	for ev in _tb().run.EVENTS:
		for o in ev.options:
			var bare: String = o.label
			for k in o:
				if o[k] is float:
					h.ok(("{%s}" % k) in o.label, "autel %s : le nombre « %s » (%s) n'est pas dit par le libellé « %s »" % [ev.id, k, str(o[k]), o.label])
					bare = bare.replace("{%s}" % k, "")
			h.ok(digits.search(bare) == null, "autel %s : nombre écrit en dur dans le libellé « %s »" % [ev.id, o.label])
	h.ok(true)

static func _base_ai_fields(h) -> void:
	var t := _t()
	_same_set(h, BASE_AI_FIELDS.keys(), D6Data.BASE_KINDS, "BASE_AI_FIELDS : une entrée par archétype d'origine")
	for kind in BASE_AI_FIELDS:
		for field in BASE_AI_FIELDS[kind]:
			h.ok(t.enemies.get(kind, {}).get(field) is float, "%s.%s : réglage lu par son IA, absent ou non numérique" % [kind, field])

## Les couples [minimum, maximum] et les distances qui s'emboîtent.
static func _ranges(h) -> void:
	var t := _t()
	for kind in t.enemies:
		var e: Dictionary = t.enemies[kind]
		if e.has("cooldownJitter"):
			h.ok(e.cooldownJitter[0] > 0.0 and e.cooldownJitter[0] <= e.cooldownJitter[1], "%s.cooldownJitter : attendu 0 < minimum <= maximum" % kind)
		if e.has("fleeDist") and e.has("preferredDist"):
			h.ok(e.fleeDist <= e.preferredDist, "%s : fleeDist (%s) au-delà de preferredDist (%s)" % [kind, str(e.fleeDist), str(e.preferredDist)])
	h.ok(t.enemies.imp.circleDist <= t.enemies.imp.circleWithin, "imp : l'anneau d'encerclement (circleDist) sort de la zone où il s'applique (circleWithin)")
	for where in [["guardians.reinforce", t.guardians.reinforce], ["boss.gardien.summon", t.boss.gardien.summon]]:
		h.ok(where[1].minR <= where[1].maxR, "%s : minR > maxR" % where[0])
	h.ok(t.combat.minChillMult <= t.combat.novaChillMult, "combat : novaChillMult sous le plancher minChillMult")
	h.egal(_tb().game.DEATH_DELAY, t.player.deathDelay, "table game.DEATH_DELAY : le réglage player.deathDelay")

## Entre un obstacle et un mur (ou un autre obstacle), soit rien ne passe (obstacle collé), soit le
## plus gros corps de la salle passe : jamais un couloir plus étroit qu'un corps, où la collision le
## renverrait d'un bord à l'autre.
static func _passages(h) -> void:
	var t := _t()
	var room: Dictionary = t.room
	var widest := 0.0
	for kind in t.enemies:
		widest = maxf(widest, 2.0 * t.enemies[kind].radius * t.elite.sizeMult)
	var widest_boss := 0.0
	for id in t.boss:
		widest_boss = maxf(widest_boss, 2.0 * t.boss[id].radius)
	var all: Dictionary = _tb().room.LAYOUTS.duplicate()
	all["BOSS_LAYOUT"] = _tb().room.BOSS_LAYOUT
	for id in all:
		var need: float = maxf(widest, widest_boss) if id == "BOSS_LAYOUT" else widest
		var rects: Array = all[id].map(func(o): return [o[0] * room.width - o[2] / 2.0, o[1] * room.height - o[3] / 2.0, o[0] * room.width + o[2] / 2.0, o[1] * room.height + o[3] / 2.0])
		for i in rects.size():
			var r: Array = rects[i]
			for gap in [r[0] - room.wallPad, r[1] - room.wallPad, room.width - room.wallPad - r[2], room.height - room.wallPad - r[3]]:
				h.ok(gap <= ROOM_SLACK or gap >= need, "disposition %s, obstacle %d : %s u entre lui et le mur (collé, ou au moins %s u)" % [id, i, str(gap), str(need)])
			for j in range(i + 1, rects.size()):
				var q: Array = rects[j]
				var dx: float = maxf(0.0, maxf(q[0] - r[2], r[0] - q[2]))
				var dy: float = maxf(0.0, maxf(q[1] - r[3], r[1] - q[3]))
				var between: float = sqrt(dx * dx + dy * dy)
				h.ok(between <= ROOM_SLACK or between >= need, "disposition %s, obstacles %d et %d : %s u entre eux (collés, ou au moins %s u)" % [id, i, j, str(between), str(need)])
	h.ok(true)

## Compte les valeurs de `v` qui ne sont pas à la forme que lit la simulation.
static func _bad_values(v) -> int:
	if v is int:
		return 1 # tout nombre de la simulation est un float
	if v is String:
		return 1 if v.begins_with(D6Js.EXACT_PREFIX) else 0 # préfixe réservé à la forme exacte
	var n := 0
	if v is Array:
		for x in v:
			n += _bad_values(x)
	elif v is Dictionary:
		for k in v:
			n += _bad_values(v[k])
	return n

static func _shape(h) -> void:
	h.egal(_bad_values(_t()), 0, "réglages : un entier GDScript ou un texte en « ~ »")
	h.egal(_bad_values(_tb()), 0, "tables : un entier GDScript ou un texte en « ~ »")
	var g: Dictionary = D6Game.create_game({"seed": 1.0})
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.lame.combo), "dans une partie, le combo actif EST celui de l'arme de départ")
	h.egal(D6Js.decode("~9a9999999999b93f"), 0.1, "la forme exacte « ~hex » est encore lue")
	h.egal(D6Js.decode("~ environ"), "~ environ", "un texte en « ~ » qui n'est pas un nombre reste un texte")

## Combat V3 : le maintien qui lance l'ultime est le MÊME geste pour toutes les classes.
static func _hold_time(h) -> void:
	var t := _t()
	var durees: Array = []
	for id in t.supers:
		h.ok(t.supers[id].get("holdTime") is float and t.supers[id].holdTime > 0.0, "Super %s : holdTime" % id)
		durees.append(t.supers[id].get("holdTime"))
	h.egal(durees.count(durees[0]), durees.size(), "holdTime : la même valeur pour tous les Supers (%s)" % str(durees))

static func tests(h) -> void:
	h.test("combat V3 : holdTime existe pour chaque Super et vaut la même durée pour tous", func(): _hold_time(h))
	h.test("classes : chaque arme, compétence, gadget et Super d'une classe existe, et l'arme nomme sa classe", func(): _classes(h))
	h.test("kits : aucune arme, compétence, gadget ni Super sans classe", func(): _kit_orphans(h))
	h.test("kit de départ : les blocs actifs par défaut et DEFAULT_LOADOUT existent", func(): _starter(h))
	h.test("armes : chaque coup sait quand il s'annule ; « shot » pour les armes à distance seulement", func(): _combo_cancel(h))
	h.test("bestiaire : chaque kind du ROSTER a ses données, chaque ennemi est dans le ROSTER", func(): _roster(h))
	h.test("bestiaire : les listes de kinds (mêlée, tireurs, champions, exclusions, invocations) nomment des ennemis", func(): _kind_lists(h))
	h.test("télégraphes : tout ennemi qui frappe s'annonce au moins 0,4 s, champion compris", func(): _enemy_telegraphs(h))
	h.test("Gardiens : rotation, renforts et invocations nomment des données qui existent", func(): _guardians(h))
	h.test("Gardiens : aucune annonce d'attaque plus courte que GUARDIAN_MIN_TELE", func(): _guardian_telegraphs(h))
	h.test("salles : chaque disposition citée par un Cercle existe, aucune n'est orpheline", func(): _layouts(h))
	h.test("salles : chaque obstacle tient dans la salle", func(): _obstacles(h))
	h.test("Cercles : un par nom plus la finale, portes connues", func(): _circles(h))
	h.test("section : chaque rythme couvre la section et finit par le Gardien", func(): _section(h))
	h.test("récompenses : chaque porte a son libellé", func(): _rewards(h))
	h.test("bénédictions : familles connues, identifiants uniques, aucune famille vide", func(): _boons(h))
	h.test("autels : identifiants uniques, chaque pacte proposé existe", func(): _altars(h))
	h.test("butin : raretés, emplacements et affixes se répondent", func(): _loot(h))
	h.test("Ville : un coût par niveau d'amélioration", func(): _town(h))
	h.test("labo : chaque variante règle un nombre qui existe, la référence décrit le défaut", func(): _lab(h))
	h.test("données : chaque nombre n'existe qu'une fois, tables et réglages recomposés se répondent", func(): _recomposed(h))
	h.test("données : tout nombre est un float, la forme exacte reste lue", func(): _shape(h))
	h.test("autels : chaque effet a dans son option les champs qu'il lit ; raretés et familles connues", func(): _altar_fields(h))
	h.test("autels : tout chiffre d'un libellé vient d'un {champ} de l'option, et tout nombre d'option y est dit", func(): _altar_labels(h))
	h.test("bestiaire : chaque archétype d'origine a les réglages que son IA lit", func(): _base_ai_fields(h))
	h.test("réglages : minimum <= maximum, distances emboîtées", func(): _ranges(h))
	h.test("salles : entre un obstacle et un mur ou un autre obstacle, rien ne passe ou le plus gros corps passe", func(): _passages(h))
