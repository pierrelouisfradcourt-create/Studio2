extends SceneTree

## Oracle des données d'un jeu, en ligne de commande.
##   godot --headless --path <jeu> --script res://addons/studio_kit/outils/valider.gd [-- res://data/validation.json]
## Sortie 0 = toutes les données valides ; 1 = au moins une faute (listée avec son chemin exact).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var config := args[0] if args.size() > 0 else StudioValidation.CONFIG_DEFAUT
	var rapport := StudioValidation.tout(config)
	var total := StudioValidation.compter(rapport)
	for fichier in rapport:
		var fautes: Array = rapport[fichier]
		print("%s %s" % ["OK   " if fautes.is_empty() else "FAUX ", fichier])
		for f in fautes:
			print("       - %s" % f)
	print("=== DONNÉES : %d fichier(s), %d faute(s) ===" % [rapport.size(), total])
	quit(0 if total == 0 and not rapport.is_empty() else 1)
