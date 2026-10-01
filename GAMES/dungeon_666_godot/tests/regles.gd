extends SceneTree
## Lance les tests de RÈGLES du jeu (tests/regles/*.gd), portés de la version web.
##   <godot> --headless --path . --script res://tests/regles.gd [-- nom_de_fichier …]
## Sortie 0 = tout vert, 1 = au moins un rouge (ou aucun test trouvé).
## Chaque fichier expose `static func tests(h)` et appelle `h.test(nom, func(): …)` (tests/harnais.gd).

const Harnais = preload("res://tests/harnais.gd")
const DOSSIER := "res://tests/regles/"

func _initialize() -> void:
	var voulus: Array = Array(OS.get_cmdline_user_args())
	var h := Harnais.new()
	var fichiers: Array = []
	for f in DirAccess.get_files_at(DOSSIER):
		if f.ends_with(".gd") and (voulus.is_empty() or f.trim_suffix(".gd") in voulus):
			fichiers.append(f)
	fichiers.sort()
	for f in fichiers:
		var avant: int = h.total
		var rouges_avant: int = h.rouges.size()
		h.fichier = f.trim_suffix(".gd")
		var script = load(DOSSIER + f)
		if script == null or not script.has_method("tests"):
			h.rouges.append({"fichier": h.fichier, "nom": "(chargement)", "message": "script illisible ou sans tests(h)"})
			print("  ROUGE — %s : script illisible ou sans tests(h)" % f)
			continue
		script.tests(h)
		print("%s : %d tests, %d rouges" % [h.fichier, h.total - avant, h.rouges.size() - rouges_avant])
	print("%d fichiers, %d tests, %d affirmations, %d rouges" % [fichiers.size(), h.total, h.affirmations, h.rouges.size()])
	var vert: bool = h.rouges.is_empty() and h.total > 0
	print("REGLES: %s" % ("PASS" if vert else "FAIL"))
	quit(0 if vert else 1)
