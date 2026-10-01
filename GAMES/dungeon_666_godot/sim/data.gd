class_name D6Data
extends RefCounted
## Données du jeu : tous les nombres (data/tuning.json) et toutes les tables (data/tables.json),
## exportés de la simulation web par `node tools/export_godot.mjs données`. Portage de la partie
## « code » de src/sim/config.mjs (createTuning) ; les fichiers de données JavaScript (kits,
## foe_data, boss_data, town_data) n'ont pas d'équivalent GDScript : ils SONT ces deux fichiers.

const SIM_HZ := 60.0
const DT := 1.0 / 60.0
const DEG := PI / 180.0
const TUNING_PATH := "res://data/tuning.json"
const TABLES_PATH := "res://data/tables.json"

static var _tuning = null
static var _tables = null

## Tables de données par module JavaScript : tables().boons.BOONS, tables().room.ROSTER…
## PARTAGÉES : ne jamais les modifier (copier avec D6Js.clone avant d'écrire dedans).
static func tables() -> Dictionary:
	if _tables == null:
		_tables = D6Js.read_exact(TABLES_PATH)
		assert(_tables is Dictionary, "data/tables.json illisible")
	return _tables

## Réglages par défaut. PARTAGÉS : ne jamais les modifier (une partie reçoit create_tuning()).
static func default_tuning() -> Dictionary:
	if _tuning == null:
		_tuning = D6Js.read_exact(TUNING_PATH)
		assert(_tuning is Dictionary, "data/tuning.json illisible")
	return _tuning

## Copie profonde des défauts, que la partie possède et peut modifier ; `overrides` (dictionnaire
## partiel) y est fusionné. Comme en JavaScript, les blocs ACTIFS sont les mêmes objets que
## l'entrée de kit qu'ils désignent (t.combo est t.weapons.lame.combo) : une surcharge de
## t.skill modifie aussi t.skills.lance.
static func create_tuning(overrides = null) -> Dictionary:
	var t: Dictionary = default_tuning().duplicate(true)
	t.combo = t.weapons.lame.combo
	t.dashStrike = t.weapons.lame.dashStrike
	t.skill = t.skills.lance
	t.gadget = t.gadgets.nova
	t["super"] = t.supers.colere
	if overrides is Dictionary:
		D6Js.deep_merge(t, overrides)
	return t
