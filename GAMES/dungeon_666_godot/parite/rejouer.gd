extends SceneTree
## Rejoue les parties notées par la simulation web et dit, pour chacune, si la partie Godot est
## la même.
##   <godot> --headless --path . --script res://parite/rejouer.gd [-- nom_de_trace …]
## Sortie 0 = toutes identiques, 1 = au moins une divergence, 2 = aucune trace à rejouer.
## Les traces viennent de `node tools/export_godot.mjs traces` (GAMES/dungeon_666).

const Rejeu = preload("res://parite/rejeu.gd")

func _initialize() -> void:
	var wanted: Array = Array(OS.get_cmdline_user_args())
	var names: Array = wanted if not wanted.is_empty() else Rejeu.names()
	if names.is_empty():
		print("aucune trace dans ", Rejeu.TRACES_DIR)
		quit(2)
		return
	var bad := 0
	var checks := 0
	for n in names:
		var trace = Rejeu.load_trace(n)
		if trace == null:
			bad += 1
			print("  ROUGE — %s : trace illisible" % n)
			continue
		var r: Dictionary = Rejeu.replay(trace)
		checks += r.checks
		if r.ok:
			print("  ok   — %s : %d points de contrôle, %d pas" % [n, r.checks, r.steps])
		else:
			bad += 1
			print("  ROUGE — %s : %s" % [n, r.message])
	print("%d parties rejouées, %d points de contrôle, %d divergentes" % [names.size(), checks, bad])
	print("PARITE: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
