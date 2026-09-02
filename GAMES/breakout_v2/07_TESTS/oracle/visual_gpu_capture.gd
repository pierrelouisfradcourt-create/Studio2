# visual_gpu_capture.gd — oracle (pixel) de la ligne proof.visual_gpu_window. Preuve VISUELLE
# par LECTEUR REEL : instancie la scene principale, laisse tourner quelques frames, capture
# l'image du viewport et prouve qu'elle est NON MONOCHROME (un rendu reel a eu lieu).
# CONTRAINTE DE POSTE (charter, mesure 2026-07-22) : exige une fenetre GPU reelle
# (--rendering-driver vulkan, fenetre hors ecran) ; --headless rend une texture NULLE.
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
	var scene = load("res://main.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	for _i in range(20):
		await process_frame
	var tex := root.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	var w: int = img.get_width() if img != null else 0
	var hgt: int = img.get_height() if img != null else 0
	var ok: bool = Capture.est_non_monochrome(img)
	print("ORACLE visual_gpu_capture: %s (image %dx%d)" % [("PASS" if ok else "FAIL"), w, hgt])
	quit(0 if ok else 1)
