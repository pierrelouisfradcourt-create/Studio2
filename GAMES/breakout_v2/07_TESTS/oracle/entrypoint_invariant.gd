# entrypoint_invariant.gd — oracle (bot_action) de la ligne proof.entrypoint_invariant. Leçon
# de cloture Snake (proof_never_replaces_product_run) : un projet peut satisfaire tous ses
# oracles et NE PAS DEMARRER. On verifie le point d'entree en ABSENCE comme en presence :
# project.godot existe, declare une main_scene, et cette scene se CHARGE reellement.
extends SceneTree

func _initialize() -> void:
	var fails: Array = []

	# (1) project.godot present (ABSENCE = echec, jamais un vert par defaut).
	var pf := FileAccess.open("res://project.godot", FileAccess.READ)
	if pf == null:
		fails.append("project.godot ABSENT : le projet ne peut pas demarrer")
	else:
		var txt := pf.get_as_text()
		pf.close()
		# (2) une main_scene est declaree.
		var i := txt.find("run/main_scene=")
		if i < 0:
			fails.append("project.godot ne declare pas run/main_scene")
		else:
			var reste := txt.substr(i + "run/main_scene=".length())
			var fin := reste.find("\n")
			var val := (reste if fin < 0 else reste.substr(0, fin)).strip_edges().replace("\"", "")
			# (3) la scene declaree existe et se CHARGE.
			if not ResourceLoader.exists(val):
				fails.append("main_scene declaree introuvable : %s" % val)
			else:
				var scene = load(val)
				if scene == null:
					fails.append("main_scene ne se charge pas : %s" % val)
				elif not (scene is PackedScene):
					fails.append("main_scene n'est pas une PackedScene : %s" % val)
				else:
					var inst = scene.instantiate()
					if inst == null:
						fails.append("main_scene ne s'instancie pas")
					else:
						inst.free()

	print("ORACLE entrypoint_invariant: %s" % ("PASS" if fails.is_empty() else "FAIL"))
	for f in fails:
		print("  FAIL: ", f)
	quit(0 if fails.is_empty() else 1)
