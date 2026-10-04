class_name D6Data
extends RefCounted
## Données du jeu : tous les nombres et toutes les tables, lus dans data/*.json — des fichiers JSON
## ordinaires, un par domaine, que l'on règle à la main (mode d'emploi : README.md, « Régler un
## nombre » ; gardes : data/validation.json et tests/regles/donnees.gd).
##
## Chaque nombre n'existe qu'UNE fois sur disque. Ce module recompose en mémoire les deux formes
## que lisent la simulation et les tests :
##   default_tuning()  les réglages d'une partie (game.tuning en est une copie) ;
##   tables()          les tables par module : tables().boons.BOONS, tables().room.ROSTER…
## Dans un fichier de données : une clé en minuscules est un bloc de réglages (tuning.<clé>), une
## clé en MAJUSCULES une table, une clé qui commence par « _ » une note pour qui règle (ignorée).
##
## Les nombres que Godot relit de ces fichiers SONT la référence (depuis le 2026-10-01 ; avant, ils
## étaient exportés de la version web : parite/LISEZ_MOI.md).

const SIM_HZ := 60.0
const DT := 1.0 / 60.0
const DEG := PI / 180.0
const DATA_DIR := "res://data/"
## Les fichiers de données, dans l'ordre où une personne les lirait.
const FILES := ["heros", "classes", "bestiaire", "gardiens", "salles", "etages", "benedictions", "butin", "autels", "ville", "labo"]
## Le bestiaire et le Gardien d'origine. Les tables EXTRA_* (lues par les tests) sont « tout le
## reste » : un ennemi ajouté dans data/bestiaire.json y entre de lui-même.
const BASE_KINDS := ["imp", "archer", "brute", "charger", "exploder"]
const BASE_BOSSES := ["gardien"]

static var _tuning = null
static var _tables = null

## Tables de données par module : tables().boons.BOONS, tables().room.ROSTER…
## PARTAGÉES : ne jamais les modifier (copier avec D6Js.clone avant d'écrire dedans).
static func tables() -> Dictionary:
	if _tables == null:
		_load()
	return _tables

## Réglages par défaut. PARTAGÉS : ne jamais les modifier (une partie reçoit create_tuning()).
static func default_tuning() -> Dictionary:
	if _tuning == null:
		_load()
	return _tuning

## Copie profonde des défauts, que la partie possède et peut modifier ; `overrides` (dictionnaire
## partiel) y est fusionné. Les blocs ACTIFS sont les mêmes objets que l'entrée de kit qu'ils
## désignent (t.combo est t.weapons.lame.combo) : une surcharge de t.combo modifie aussi
## t.weapons.lame.combo. Compétences et gadgets n'ont pas de bloc actif : ils se lisent par
## emplacement (D6Loadout.slot_def). t.dash est le bloc actif du DÉPLACEMENT DE CLASSE : le dash
## de base (data/heros.json), que D6Loadout.resolve_kit complète par le déplacement de la classe
## (t.moves, data/classes.json) quand ce n'est pas le dash.
static func create_tuning(overrides = null) -> Dictionary:
	var t: Dictionary = default_tuning().duplicate(true)
	t.combo = t.weapons.lame.combo
	t.dashStrike = t.weapons.lame.dashStrike
	t["super"] = t.supers.colere
	if overrides is Dictionary:
		D6Js.deep_merge(t, overrides)
	return t

# ---------------------------------------------------------------- lecture et recomposition

## Les fichiers de données décodés : {nom: contenu}. Un fichier manquant ou illisible est une erreur.
static func read_files() -> Dictionary:
	var out := {}
	for name in FILES:
		var content = D6Js.read_exact(DATA_DIR + name + ".json")
		if not (content is Dictionary):
			push_error("data/%s.json manquant ou illisible" % name)
			content = {}
		out[name] = content
	return out

static func _load() -> void:
	var f := read_files()
	_tuning = _build_tuning(f)
	_tables = _build_tables(f, _tuning)

## Les réglages, dans l'ordre de leurs clés (des boucles le parcourent : il fait partie des règles).
## combo, dashStrike et super sont les blocs du kit de départ, recopiés.
static func _build_tuning(f: Dictionary) -> Dictionary:
	var h: Dictionary = f.heros
	var k: Dictionary = f.classes
	var e: Dictionary = f.etages
	return {
		"player": h.player, "weaponBase": h.weaponBase, "armorBase": h.armorBase, "hitstopBank": h.hitstopBank,
		"hitstopMode": h.hitstopMode, "killHitstop": h.killHitstop, "dash": h.dash,
		"combo": D6Js.clone(k.weapons.lame.combo),
		"comboResetTime": h.comboResetTime, "comboCancelFrom": h.comboCancelFrom,
		"dashStrike": D6Js.clone(k.weapons.lame.dashStrike),
		"wallSlam": h.wallSlam, "autoAim": h.autoAim,
		"super": D6Js.clone(k.supers.colere),
		"classes": k.classes, "weapons": k.weapons, "skills": k.skills, "gadgets": k.gadgets, "supers": k.supers,
		"lab": f.labo.lab,
		"enemies": f.bestiaire.enemies, "elite": f.bestiaire.elite, "boss": f.gardiens.boss,
		"combat": h.combat, "room": f.salles.room,
		"floors": e.floors, "section": e.section, "encounter": e.encounter, "circles": e.circles,
		"guardians": f.gardiens.guardians, "progression": f.ville.progression, "town": f.ville.town,
		"economy": f.butin.economy, "loot": f.butin.loot, "boons": f.benedictions.boons,
		"moves": k.moves,
	}

## Les tables, par module et dans l'ordre d'origine. Ce qui répète un réglage en est une COPIE
## (les tables ne changent jamais ; les réglages d'une partie, si).
static func _build_tables(f: Dictionary, t: Dictionary) -> Dictionary:
	var b: Dictionary = f.bestiaire
	var s: Dictionary = f.salles
	var e: Dictionary = f.etages
	return {
		"ai_common": _pick(b, ["MELEE_KINDS", "SHOOTER_KINDS"]),
		"boons": _pick(f.benedictions, ["BOONS", "DUOS", "FAMILIES", "PACTS", "RARITIES"]),
		"boss_data": {
			"EXTRA_BOSSES": _without(t.boss, BASE_BOSSES),
			"GUARDIAN_MIN_TELE": f.gardiens.GUARDIAN_MIN_TELE,
			"GUARDIAN_ROTATION": D6Js.clone(t.guardians.rotation),
		},
		"calm_rooms": _pick(s, ["CALM_KINDS"]),
		"config": {"DEG": DEG, "DT": DT, "SIM_HZ": SIM_HZ},
		"foe_data": {
			"EXTRA_ELITE_KINDS": b.EXTRA_ELITE_KINDS,
			"EXTRA_ENEMIES": _without(t.enemies, BASE_KINDS),
			"EXTRA_ROSTER": D6Js.clone(b.ROSTER.filter(func(r): return not BASE_KINDS.has(r.kind))),
		},
		"game": {"DEATH_DELAY": t.player.deathDelay, "DT": DT},
		"kits": {
			"CLASSES": D6Js.clone(t.classes), "DEFAULT_LOADOUT": f.classes.DEFAULT_LOADOUT, "GADGETS": D6Js.clone(t.gadgets),
			"SKILLS": D6Js.clone(t.skills), "SUPERS": D6Js.clone(t.supers), "WEAPONS": D6Js.clone(t.weapons),
		},
		"lab": _pick(f.labo, ["LAB_AXES"]),
		"loot": _pick(f.butin, ["AFFIXES", "BASES", "ITEM_RARITIES", "LEGENDARY_POWERS", "SLOTS", "SLOT_NAMES", "STAT_LABELS"]),
		"profile": {"EQUIP_SLOTS": D6Js.clone(f.butin.SLOTS), "PROFILE_SCHEMA": f.ville.PROFILE_SCHEMA, "STASH_MAX": f.ville.STASH_MAX},
		"room": {
			"BOSS_LAYOUT": s.BOSS_LAYOUT, "COMBAT_LAYOUTS": s.COMBAT_LAYOUTS, "LAYOUTS": s.LAYOUTS,
			"LAYOUT_IDS": s.LAYOUTS.keys(), "ROSTER": b.ROSTER, "TERRAINS": s.TERRAINS,
		},
		"run": {"EVENTS": f.autels.EVENTS, "REWARD_LABELS": e.REWARD_LABELS},
		"sections": _pick(e, ["FLOOR_TYPE_OF_REWARD"]),
		"town_data": {"SALVAGE_SOULS": D6Js.clone(t.town.salvageSouls), "UPGRADES": D6Js.clone(t.town.upgrades)},
	}

static func _pick(d: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key in keys:
		out[key] = d[key]
	return out

## Copie de `d` sans les clés `excluded`.
static func _without(d: Dictionary, excluded: Array) -> Dictionary:
	var out := {}
	for key in d:
		if not excluded.has(key):
			out[key] = D6Js.clone(d[key])
	return out
