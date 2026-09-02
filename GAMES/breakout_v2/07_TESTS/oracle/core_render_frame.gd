# core_render_frame.gd — oracle (pixel) de la ligne core.render. L'executable rend REELLEMENT
# une image (leçon Snake proof_never_replaces_product_run : un projet peut passer tous ses
# oracles et ne rien afficher). On instancie la scene principale, on laisse rendre, et on
# prouve que le viewport porte une image NON MONOCHROME. Fenetre GPU reelle exigee (charter).
#
# forge:run_mode = gpu_window
#
# DIRECTIVE STATIQUE lue par le collecteur (scripts/forge/product_oracle_godot.py) AVANT
# execution : ce volet CAPTURE des pixels (viewport/get_image), il doit donc etre lance en
# fenetre GPU hors ecran et non en --headless, qui rend une texture NULLE et fabriquerait
# un rouge. L exigence etait deja ecrite ci-dessus EN PROSE ; la prose ne route rien.
# Aucun comportement de ce volet n est modifie par cette ligne.
extends SceneTree

const Capture = preload("res://06_RUNTIME/adapters/presentation/capture.gd")

func _initialize() -> void:
	var inst = load("res://main.tscn").instantiate()
	root.add_child(inst)
	for _i in range(15):
		await process_frame
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	var ok: bool = Capture.est_non_monochrome(img)
	print("ORACLE core_render_frame: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
