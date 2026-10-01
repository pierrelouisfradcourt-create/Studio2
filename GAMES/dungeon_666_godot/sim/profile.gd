class_name D6Profile
extends RefCounted
## Portage de src/sim/profile.mjs.
## PROFIL PERMANENT — tout ce que la mort ne reprend JAMAIS.
##
##   PERMANENT (ce fichier)            TEMPORAIRE (game.run, remis à zéro à la mort)
##   classe, armes, équipement,        bénédictions (bonus, pouvoirs, améliorations,
##   coffre, compétences, gadgets,     synergies de build), PV, charges, étage courant
##   déblocages de la Ville, Âmes,
##   checkpoints / points de TP
##
## L'or est la bourse du héros : elle le suit d'un run à l'autre, mais Charon prélève sa part
## à chaque mort (economy.deathGoldKeep). Les Âmes, elles, ne se perdent jamais.
##
## Fonctions PURES sur des dictionnaires (aucun nœud) : la Ville appelle ces opérations, le
## programme principal sauvegarde le résultat. Chaque opération rend { ok, reason? }.
## PROFILE_SCHEMA, STASH_MAX, EQUIP_SLOTS : D6Data.tables().profile.

const DEFAULT_WEAPON := "lame"
const KINDS := ["classes", "weapons", "skills", "gadgets"]

static func _t() -> Dictionary:
	return D6Data.tables().profile

## Profil d'un nouveau joueur. `tuning` : pour connaître le kit de départ.
static func create_profile(tuning: Dictionary) -> Dictionary:
	var start := _starting_kit(tuning)
	return {
		"schema": _t().PROFILE_SCHEMA,
		"checkpoints": [1.0], # étages où l'on peut (re)partir : 1, puis l'étage qui suit chaque Gardien
		"bestFloor": 1.0,
		"souls": 0.0, # Âmes : monnaie permanente de la Ville
		"gold": 0.0, # bourse (taxée à la mort)
		"unlocked": {
			"classes": [start.classId],
			"weapons": [start.weaponType],
			"skills": [start.skillId],
			"gadgets": [start.gadgetId],
		},
		"upgrades": {}, # id du Sanctuaire -> niveau
		"loadout": {"classId": start.classId, "skillId": start.skillId, "gadgetId": start.gadgetId},
		"equipment": {"arme": null, "armure": null, "talisman": null}, # rempli par starterItems à la 1re partie
		"stash": [],
		"itemSeq": 1.0,
		"guardians": {}, # modèle de Gardien -> victoires
		"stats": {"runs": 0.0, "deaths": 0.0, "kills": 0.0, "guardianKills": 0.0},
	}

## Profil neuf avec le kit gratuit de la classe de départ.
static func new_profile(tuning: Dictionary) -> Dictionary:
	var p := create_profile(tuning)
	grant_class_starters(p, tuning, p.loadout.classId)
	return p

## Le kit GRATUIT d'une classe (entrées de coût 0 : arme, compétence et gadget de départ) est
## acquis avec la classe ; sinon le Grimoire afficherait « Débloquer · ◆ 0 ».
static func grant_class_starters(profile: Dictionary, tuning: Dictionary, class_id) -> void:
	var c = tuning.classes.get(class_id)
	if c == null:
		return
	for kind in ["weapons", "skills", "gadgets"]:
		for id in c[kind]:
			var entry = tuning[kind].get(id)
			if D6Js.truthy(entry) and D6Js.nz(entry.get("cost"), 0.0) == 0.0 and not profile.unlocked[kind].has(id):
				profile.unlocked[kind].append(id)

static func _starting_kit(tuning: Dictionary) -> Dictionary:
	var class_id = tuning.classes.keys()[0]
	var c: Dictionary = tuning.classes[class_id]
	return {"classId": class_id, "weaponType": c.weapons[0], "skillId": c.skills[0], "gadgetId": c.gadgets[0]}

static func _is_obj(v) -> bool:
	return v is Dictionary

## Number.isFinite : un vrai nombre (ni texte, ni booléen), fini.
static func _is_number(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))

static func _int_in(v, lo: float, hi: float) -> bool:
	return _is_number(v) and float(v) == floorf(float(v)) and v >= lo and v <= hi

## Identifiants connus, sans doublon, dans l'ordre de leur 1re apparition.
static func _id_list(v, known: Array) -> Array:
	var out: Array = []
	if v is Array:
		for id in v:
			if (id is String or id is StringName) and known.has(id) and not out.has(id):
				out.append(id)
	return out

## Objet d'équipement lisible (forme minimale ; la forme évolue pendant le prototype).
static func is_item(it) -> bool:
	return _is_obj(it) and _t().EQUIP_SLOTS.has(it.get("slot")) and it.get("affixes") is Array \
		and (it.get("name") is String or it.get("name") is StringName) and _is_obj(it.get("base"))

## Profil validé champ par champ : une sauvegarde ancienne (schéma 1-2 : {checkpoints,
## bestFloor, items, snapshots}) ou corrompue retombe sur des défauts au lieu de bloquer.
## Les « instantanés de build » des anciennes versions sont abandonnés : le temporaire ne
## survit plus à la mort.
static func sanitize_profile(raw, tuning: Dictionary) -> Dictionary:
	var out := create_profile(tuning)
	if not _is_obj(raw):
		return out
	var total: float = tuning.floors.total
	_sanitize_progress(out, raw, tuning, total)
	_sanitize_unlocked(out, raw, tuning)
	if _is_obj(raw.get("upgrades")):
		var town = tuning.get("town")
		var known = town.get("upgrades") if town is Dictionary else null
		for id in raw.upgrades:
			var up = known.get(id) if known is Dictionary else null
			if D6Js.truthy(up) and _int_in(raw.upgrades[id], 0.0, up.max):
				out.upgrades[id] = raw.upgrades[id]
	if _is_obj(raw.get("loadout")):
		var l: Dictionary = raw.loadout
		if out.unlocked.classes.has(l.get("classId")):
			out.loadout.classId = l.classId
		if out.unlocked.skills.has(l.get("skillId")):
			out.loadout.skillId = l.skillId
		if out.unlocked.gadgets.has(l.get("gadgetId")):
			out.loadout.gadgetId = l.gadgetId
	_sanitize_items(out, raw)
	if _is_obj(raw.get("guardians")):
		for k in raw.guardians:
			if D6Js.truthy(tuning.boss.get(k)) and _int_in(raw.guardians[k], 0.0, 1e6):
				out.guardians[k] = raw.guardians[k]
	if _is_obj(raw.get("stats")):
		for k in out.stats.keys():
			if _int_in(raw.stats.get(k), 0.0, 1e9):
				out.stats[k] = raw.stats[k]
	fix_loadout(out, tuning)
	return out

## Checkpoints, meilleur étage, Âmes et or.
static func _sanitize_progress(out: Dictionary, raw: Dictionary, tuning: Dictionary, total: float) -> void:
	# Un checkpoint est le 1er étage d'une section (l'étage qui suit un Gardien). Ceux d'avant la
	# V2 (Gardien tous les 6 étages : 7, 13…) ne sont plus des points de reprise et sont écartés.
	var cps: Array = [1.0]
	if raw.get("checkpoints") is Array:
		for f in raw.checkpoints:
			if _int_in(f, 1.0, total) and D6Floors.floor_info(tuning, f).indexInSection == 1.0 and not cps.has(float(f)):
				cps.append(float(f))
	cps.sort() # nombres distincts : aucun départage à faire
	out.checkpoints = cps
	out.bestFloor = raw.bestFloor if _int_in(raw.get("bestFloor"), 1.0, total) else 1.0
	var souls = raw.get("souls")
	out.souls = floorf(souls) if _is_number(souls) and souls >= 0.0 else 0.0
	var gold = raw.get("gold")
	out.gold = floorf(gold) if _is_number(gold) and gold >= 0.0 else 0.0

## Déblocages : les défauts, plus les identifiants connus de la sauvegarde, plus les kits des
## classes possédées.
static func _sanitize_unlocked(out: Dictionary, raw: Dictionary, tuning: Dictionary) -> void:
	var u = raw.get("unlocked")
	if not _is_obj(u):
		u = {}
	for k in KINDS:
		var merged: Array = out.unlocked[k].duplicate()
		for id in _id_list(u.get(k), tuning[k].keys()):
			if not merged.has(id):
				merged.append(id)
		out.unlocked[k] = merged
	for c in out.unlocked.classes:
		grant_class_starters(out, tuning, c)
	for id in out.unlocked.classes:
		_grant_starter_kit(out, tuning, id)

## Équipement porté, coffre et identifiants d'objets.
static func _sanitize_items(out: Dictionary, raw: Dictionary) -> void:
	# Ancien schéma : l'équipement vivait dans `items`.
	var eq = raw.get("equipment")
	if not _is_obj(eq):
		eq = raw.get("items")
	if not _is_obj(eq):
		eq = {}
	for s in _t().EQUIP_SLOTS:
		var it = eq.get(s)
		out.equipment[s] = it if is_item(it) and it.slot == s else null
	out.stash = raw.stash.filter(is_item).slice(0, int(_t().STASH_MAX)) if raw.get("stash") is Array else []
	out.itemSeq = raw.itemSeq if _int_in(raw.get("itemSeq"), 1.0, 1e9) else 1.0
	for it in out.equipment.values() + out.stash:
		if it != null:
			ensure_uid(out, it)

## Identifiant stable d'un objet dans le profil (les `id` de partie se recyclent).
static func ensure_uid(profile: Dictionary, item: Dictionary):
	if not D6Js.truthy(item.get("uid")):
		item.uid = "i" + D6Js.num_str(profile.itemSeq)
		profile.itemSeq += 1.0
	return item.uid

## item.weaponType ?? 'lame'
static func _weapon_type(item) -> String:
	if not (item is Dictionary):
		return DEFAULT_WEAPON
	return D6Js.nz(item.get("weaponType"), DEFAULT_WEAPON)

## item.score ?? 0 ; une valeur non numérique vaut NaN (toute comparaison est alors fausse).
static func _score(item: Dictionary) -> float:
	var v = item.get("score")
	if v == null:
		return 0.0
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return NAN

static func _first_owned(list: Array, owned: Array):
	for id in list:
		if owned.has(id):
			return id
	return list[0]

## La compétence, le gadget et l'arme équipés doivent appartenir à la classe choisie.
static func fix_loadout(profile: Dictionary, tuning: Dictionary) -> void:
	var c = tuning.classes.get(profile.loadout.get("classId"))
	if c == null:
		c = tuning.classes[tuning.classes.keys()[0]]
	var l: Dictionary = profile.loadout
	if not c.skills.has(l.get("skillId")) or not profile.unlocked.skills.has(l.get("skillId")):
		l.skillId = _first_owned(c.skills, profile.unlocked.skills)
	if not c.gadgets.has(l.get("gadgetId")) or not profile.unlocked.gadgets.has(l.get("gadgetId")):
		l.gadgetId = _first_owned(c.gadgets, profile.unlocked.gadgets)
	var w = profile.equipment.get("arme")
	if w != null and not c.weapons.has(_weapon_type(w)):
		# Arme d'une autre classe : elle retourne au coffre, la meilleure arme compatible la remplace.
		_stash_push(profile, w)
		profile.equipment.arme = _take_best_from_stash(profile, "arme", func(it): return c.weapons.has(_weapon_type(it)))

static func _stash_push(profile: Dictionary, item: Dictionary) -> void:
	ensure_uid(profile, item)
	profile.stash.append(item)
	# Coffre plein : le moins bon part (jamais l'objet qu'on vient d'y ranger).
	while profile.stash.size() > _t().STASH_MAX:
		var worst := 0
		for i in range(1, profile.stash.size() - 1):
			if _score(profile.stash[i]) < _score(profile.stash[worst]):
				worst = i
		profile.stash.remove_at(worst)

static func _take_best_from_stash(profile: Dictionary, slot: String, ok: Callable):
	var best := -1
	for i in profile.stash.size():
		var it: Dictionary = profile.stash[i]
		if it.get("slot") != slot or not ok.call(it):
			continue
		if best < 0 or _score(it) > _score(profile.stash[best]):
			best = i
	return null if best < 0 else profile.stash.pop_at(best)

# ---------------------------------------------------------------- opérations de la Ville

## Table de contenu d'un genre (classes, weapons, skills, gadgets) ; null si le genre est inconnu.
static func _table(tuning: Dictionary, kind):
	return tuning.get(kind) if KINDS.has(kind) else null

## Prix de déblocage d'une entrée de contenu (0 = possédée d'office).
static func unlock_cost(tuning: Dictionary, kind, id) -> float:
	var table = _table(tuning, kind)
	var entry = table.get(id) if table is Dictionary else null
	return D6Js.nz(entry.get("cost"), 0.0) if entry is Dictionary else 0.0

static func unlock(profile: Dictionary, tuning: Dictionary, kind, id) -> Dictionary:
	var table = _table(tuning, kind)
	if not (table is Dictionary) or not D6Js.truthy(table.get(id)):
		return {"ok": false, "reason": "inconnu"}
	if profile.unlocked[kind].has(id):
		return {"ok": false, "reason": "déjà débloqué"}
	var cost := unlock_cost(tuning, kind, id)
	if profile.souls < cost:
		return {"ok": false, "reason": "Âmes insuffisantes"}
	profile.souls -= cost
	profile.unlocked[kind].append(id)
	if kind == "classes":
		grant_class_starters(profile, tuning, id)
	if kind == "classes":
		_grant_starter_kit(profile, tuning, id)
	if kind == "weapons":
		# Une arme débloquée est forgée aussitôt en exemplaire commun, rangé au coffre.
		_stash_push(profile, starter_weapon(tuning, id))
	return {"ok": true}

## Kit de départ d'une classe (1re arme, 1re compétence, 1er gadget) : possédé dès que la classe
## l'est. Sans cela, la classe choisie équipait une compétence encore « à débloquer » au Grimoire.
static func _grant_starter_kit(profile: Dictionary, tuning: Dictionary, class_id) -> void:
	var c = tuning.classes.get(class_id)
	if c == null:
		return
	for kind in ["weapons", "skills", "gadgets"]:
		var list = c.get(kind)
		var id = list[0] if list is Array and list.size() > 0 else null
		if D6Js.truthy(id) and not profile.unlocked[kind].has(id):
			profile.unlocked[kind].append(id)

## Exemplaire commun d'un type d'arme (sans affixe), pour la Forge et le départ.
static func starter_weapon(tuning: Dictionary, weapon_type) -> Dictionary:
	var w: Dictionary = tuning.weapons[weapon_type]
	return {
		"slot": "arme", "weaponType": weapon_type, "rarity": "commun", "name": D6Js.nz(w.get("starterName"), w.get("name")), "level": 1.0,
		"affixes": [], "power": null, "base": {"damage": tuning.weaponBase * D6Js.nz(w.get("baseMult"), 1.0)}, "score": 0.0,
	}

static func upgrade_cost(tuning: Dictionary, id, level: float):
	var town = tuning.get("town")
	var known = town.get("upgrades") if town is Dictionary else null
	var up = known.get(id) if known is Dictionary else null
	if not D6Js.truthy(up) or level >= up.max:
		return null
	# costs[level] : « undefined » hors du tableau ou pour un niveau non entier
	if level != floorf(level) or level < 0.0 or level >= up.costs.size():
		return null
	return up.costs[int(level)]

static func buy_upgrade(profile: Dictionary, tuning: Dictionary, id) -> Dictionary:
	var lv: float = D6Js.nz(profile.upgrades.get(id), 0.0)
	var cost = upgrade_cost(tuning, id, lv)
	if cost == null:
		return {"ok": false, "reason": "niveau maximal"}
	if profile.souls < cost:
		return {"ok": false, "reason": "Âmes insuffisantes"}
	profile.souls -= cost
	profile.upgrades[id] = lv + 1.0
	return {"ok": true}

static func select_class(profile: Dictionary, tuning: Dictionary, class_id) -> Dictionary:
	if not profile.unlocked.classes.has(class_id):
		return {"ok": false, "reason": "classe verrouillée"}
	profile.loadout.classId = class_id
	var c: Dictionary = tuning.classes[class_id]
	if not c.weapons.has(_weapon_type(profile.equipment.get("arme"))):
		if profile.equipment.get("arme") != null:
			_stash_push(profile, profile.equipment.arme)
		profile.equipment.arme = _take_best_from_stash(profile, "arme", func(it): return c.weapons.has(_weapon_type(it)))
		# Aucune arme de la classe au coffre : on forge l'arme de départ (toujours disponible).
		if profile.equipment.arme == null:
			var wt = _first_owned(c.weapons, profile.unlocked.weapons)
			if not profile.unlocked.weapons.has(wt):
				profile.unlocked.weapons.append(wt)
			profile.equipment.arme = starter_weapon(tuning, wt)
			ensure_uid(profile, profile.equipment.arme)
	fix_loadout(profile, tuning)
	return {"ok": true}

static func select_skill(profile: Dictionary, tuning: Dictionary, skill_id) -> Dictionary:
	var c: Dictionary = tuning.classes[profile.loadout.classId]
	if not profile.unlocked.skills.has(skill_id) or not c.skills.has(skill_id):
		return {"ok": false, "reason": "indisponible"}
	profile.loadout.skillId = skill_id
	return {"ok": true}

static func select_gadget(profile: Dictionary, tuning: Dictionary, gadget_id) -> Dictionary:
	var c: Dictionary = tuning.classes[profile.loadout.classId]
	if not profile.unlocked.gadgets.has(gadget_id) or not c.gadgets.has(gadget_id):
		return {"ok": false, "reason": "indisponible"}
	profile.loadout.gadgetId = gadget_id
	return {"ok": true}

## Rang dans le coffre de l'objet d'identifiant `uid` (findIndex : -1 s'il n'y est pas).
static func _stash_index(profile: Dictionary, uid) -> int:
	for i in profile.stash.size():
		if _same_value(profile.stash[i].get("uid"), uid):
			return i
	return -1

## a === b sur des valeurs simples (textes, nombres, null) : jamais d'égalité entre types.
static func _same_value(a, b) -> bool:
	var a_text: bool = a is String or a is StringName
	var b_text: bool = b is String or b is StringName
	if a_text or b_text:
		return a_text and b_text and String(a) == String(b)
	var a_num: bool = typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT
	var b_num: bool = typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT
	if a_num or b_num:
		return a_num and b_num and float(a) == float(b)
	return typeof(a) == typeof(b) and a == b

## Équipe un objet du coffre ; l'objet porté prend sa place au coffre.
static func equip_from_stash(profile: Dictionary, tuning: Dictionary, uid) -> Dictionary:
	var i := _stash_index(profile, uid)
	if i < 0:
		return {"ok": false, "reason": "objet introuvable"}
	var item: Dictionary = profile.stash[i]
	if item.slot == "arme":
		var c: Dictionary = tuning.classes[profile.loadout.classId]
		if not c.weapons.has(_weapon_type(item)):
			return {"ok": false, "reason": "arme réservée à une autre classe"}
	profile.stash.remove_at(i)
	var cur = profile.equipment.get(item.slot)
	profile.equipment[item.slot] = item
	if cur != null:
		_stash_push(profile, cur)
	return {"ok": true}

## Recycle un objet du coffre en Âmes.
static func salvage_from_stash(profile: Dictionary, tuning: Dictionary, uid) -> Dictionary:
	var i := _stash_index(profile, uid)
	if i < 0:
		return {"ok": false, "reason": "objet introuvable"}
	var item: Dictionary = profile.stash.pop_at(i)
	profile.souls += salvage_souls(tuning, item)
	return {"ok": true}

static func salvage_souls(tuning: Dictionary, item: Dictionary) -> float:
	var town = tuning.get("town")
	var table = town.get("salvageSouls") if town is Dictionary else null
	if table == null:
		table = {"commun": 1.0, "magique": 3.0, "rare": 8.0, "legendaire": 20.0}
	return D6Js.nz(table.get(item.get("rarity")), 1.0)

## Un objet trouvé en donjon qu'on ne porte pas file au coffre (il n'est jamais perdu).
static func stash_loot(profile: Dictionary, item: Dictionary) -> void:
	_stash_push(profile, item)
