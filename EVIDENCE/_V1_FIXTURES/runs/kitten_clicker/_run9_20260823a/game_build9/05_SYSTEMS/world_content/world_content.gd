# world_content.gd — LOGIQUE PURE (category system, allowed_deps []).
# Source UNIQUE du contenu declare du monde : charge et VALIDE les 4 registres
# 03_WORLD/rules/{kittens,places,objects,quests}.json et expose leur cardinalite. Aucun
# autre systeme ne redeclare de contenu. Deterministe : lecture de fichiers de donnees,
# aucun alea, aucune horloge.
extends RefCounted

# --- cardinalites minimales ISOLEES (garde-fou (d)) -------------------------------
const MIN_KITTENS: int = 6
const MIN_PLACES: int = 2
const MIN_OBJECTS: int = 3
const MIN_QUESTS: int = 3

const RULES_DIR: String = "res://03_WORLD/rules/world_content/"

# Extraction PURE de la liste sous `key` d'un JSON parse (injecte) : testable a la frontiere
# (Dictionary present mais valeur non-Array, ou l'inverse) sans lire de fichier.
static func extract_array(parsed, key: String) -> Array:
	if parsed is Dictionary and parsed.get(key) is Array:
		return parsed[key]
	return []

static func _read_array(filename: String, key: String) -> Array:
	var path: String = RULES_DIR + filename
	if not FileAccess.file_exists(path):
		return []
	return extract_array(JSON.parse_string(FileAccess.get_file_as_string(path)), key)

static func kittens() -> Array:
	return _read_array("kittens.json", "kittens")

static func places() -> Array:
	return _read_array("places.json", "places")

static func objects() -> Array:
	return _read_array("objects.json", "objects")

static func quests() -> Array:
	return _read_array("quests.json", "quests")

# Nombre de NOMS de chatons distincts (l'exigence porte sur des chatons NOMMES distincts).
static func distinct_kitten_names(kittens_array: Array) -> int:
	var seen: Array = []
	for k in kittens_array:
		if k is Dictionary:
			var n: String = String(k.get("name", ""))
			if n != "" and not seen.has(n):
				seen.append(n)
	return seen.size()

# La place de tier 0 existe-t-elle (le refuge de depart) ?
static func has_refuge(places_array: Array) -> bool:
	for p in places_array:
		if p is Dictionary and int(p.get("unlock_tier", -1)) == 0:
			return true
	return false

# Les 4 registres INJECTES satisfont-ils leur cardinalite et schema minimal ? Pur (arrays
# injectes) pour etre testable a la frontiere (chaque condition falsifiable independamment).
static func registers_valid(ks: Array, ps: Array, objs: Array, qs: Array) -> bool:
	return (distinct_kitten_names(ks) >= MIN_KITTENS
		and ps.size() >= MIN_PLACES and has_refuge(ps)
		and objs.size() >= MIN_OBJECTS
		and qs.size() >= MIN_QUESTS)

# Les 4 registres reels (03_WORLD) satisfont-ils leur cardinalite et schema minimal ?
static func valid() -> bool:
	return registers_valid(kittens(), places(), objects(), quests())
