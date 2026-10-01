extends SceneTree
## Point d'entrée de l'oracle headless de Dungeon 666 (version Godot).
##   <godot> --headless --path GAMES/dungeon_666_godot --script res://tests/run_tests.gd
## Sortie 0 = tout vert, 1 = au moins un rouge.
##
## Ce que l'oracle prouve : la simulation Godot calcule ce que calcule la simulation web
## (GAMES/dungeon_666, la spécification), sur les vecteurs et les parties exportés par
## `node tools/export_godot.mjs`. Il ne prouve ni le rendu ni le plaisir de jeu.
##
## Garde anti-faux-vert : chaque module de vecteurs attendu doit être présent, sans fonction
## orpheline, avec au moins MIN_CASES cas ; un fichier manquant ou vide est un ROUGE.

const MIN_CASES := 50
const EXPECTED_VECTOR_MODULES := ["trig", "geo", "rng", "physics", "nav", "aim", "spawns", "combat", "projectiles", "state", "floors", "lab", "loadout", "profile", "boons", "loot", "stats", "sections"]

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  ok   — ", label)
	else:
		_fails += 1
		print("  ROUGE — ", label)

func _initialize() -> void:
	_vectors()
	_data()
	print("%d vérifications, %d rouges" % [_checks, _fails])
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)

func _vectors() -> void:
	print("[vecteurs] fonctions pures contre la simulation web")
	var present: Array = D6Vecteurs.modules()
	for m in EXPECTED_VECTOR_MODULES:
		_ok(present.has(m), "module de vecteurs présent : %s" % m)
	for m in present:
		var r: Dictionary = D6Vecteurs.run(m)
		for f in r.fails:
			print("      ", f)
		_ok(r.missing.is_empty(), "%s : toutes les fonctions ont leur portage %s" % [m, str(r.missing) if not r.missing.is_empty() else ""])
		_ok(r.cases >= MIN_CASES, "%s : %d cas joués (minimum %d)" % [m, r.cases, MIN_CASES])
		_ok(r.fails.is_empty(), "%s : %d cas identiques à la référence" % [m, r.cases])

func _data() -> void:
	print("[données] réglages exportés de la simulation web")
	var t = D6Js.read_exact("res://data/tuning.json")
	_ok(t is Dictionary, "data/tuning.json lisible")
	if t is Dictionary:
		_ok(t.player.speed == 300.0 and t.floors.total == 666.0, "réglages de référence (vitesse 300, 666 étages)")
		# 0,083 : un décimal que Godot ne lit PAS comme JavaScript ; la forme exacte doit le rendre au bit près.
		_ok(t.player.accelTime == 0.083, "nombre décimal reconstruit à l'identique (accelTime)")
	var tables = D6Js.read_exact("res://data/tables.json")
	_ok(tables is Dictionary and tables.has("boons") and tables.has("kits"), "data/tables.json lisible")
