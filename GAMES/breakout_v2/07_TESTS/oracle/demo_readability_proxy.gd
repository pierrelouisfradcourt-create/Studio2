# demo_readability_proxy.gd — oracle (pixel) de la ligne render.gameplay_readability. Proxy
# MECANIQUE de lisibilite : un rendu lisible distingue plusieurs elements (fond, rangees de
# briques colorees, raquette, balle) -> l'image porte un nombre eleve de couleurs distinctes
# (>= 6, l'ordre de grandeur des 6 rangees de briques + fond/raquette/balle). Fenetre GPU exigee.
#
# forge:run_mode = gpu_window
#
# DIRECTIVE STATIQUE lue par le collecteur (scripts/forge/product_oracle_godot.py) AVANT
# execution : ce volet CAPTURE des pixels (viewport/get_image), il doit donc etre lance en
# fenetre GPU hors ecran et non en --headless, qui rend une texture NULLE et fabriquerait
# un rouge. L exigence etait deja ecrite ci-dessus EN PROSE ; la prose ne route rien.
# Aucun comportement de ce volet n est modifie par cette ligne.
extends SceneTree

func _couleurs_distinctes(img: Image) -> int:
	if img == null:
		return 0
	var vues := {}
	var px := maxi(1, img.get_width() / 60)
	var py := maxi(1, img.get_height() / 60)
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			vues[img.get_pixel(x, y).to_rgba32()] = true
			x += px
		y += py
	return vues.size()

func _initialize() -> void:
	var inst = load("res://main.tscn").instantiate()
	root.add_child(inst)
	for _i in range(10):
		await process_frame
	var img: Image = root.get_texture().get_image()
	var n := _couleurs_distinctes(img)
	var ok := n >= 6
	var fails: Array = []
	if not ok:
		fails.append("moins de 6 couleurs distinctes (%d) — fenetre GPU requise (--headless rend une texture nulle)" % n)
	print("FORGE_ORACLE demo_readability_proxy " + JSON.stringify({"ok": ok, "fails": fails, "data": {"couleurs_distinctes": n, "seuil": 6}}))
	quit(0 if ok else 1)
