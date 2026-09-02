# demo_brick_destruction.gd — oracle (pixel) de la ligne render.brick_destruction. Au contact,
# la brique DISPARAIT visiblement : on capture la zone des briques, on detruit des briques dans
# l'etat, et la meme zone du rendu CHANGE (des pixels de brique deviennent fond). La zone
# echantillonnee (haut du terrain) exclut la balle (qui part vers le bas). Fenetre GPU exigee.
#
# forge:run_mode = gpu_window
#
# DIRECTIVE STATIQUE lue par le collecteur (scripts/forge/product_oracle_godot.py) AVANT
# execution : ce volet CAPTURE des pixels (viewport/get_image), il doit donc etre lance en
# fenetre GPU hors ecran et non en --headless, qui rend une texture NULLE et fabriquerait
# un rouge. L exigence etait deja ecrite ci-dessus EN PROSE ; la prose ne route rien.
# Aucun comportement de ce volet n est modifie par cette ligne.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")

func _diff_zone_briques(a: Image, b: Image) -> int:
	if a == null or b == null:
		return -1
	var y0 := 42
	var y1 := 232
	var changes := 0
	var y := y0
	while y < y1 and y < a.get_height():
		var x := 4
		while x < a.get_width() - 4:
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changes += 1
			x += 8
		y += 8
	return changes

func _initialize() -> void:
	var inst = load("res://main.tscn").instantiate()
	root.add_child(inst)
	for _i in range(8):
		await process_frame
	var imgA: Image = root.get_texture().get_image()

	# Detruire toutes les briques dans l'etat de jeu -> elles doivent disparaitre du rendu.
	var s = inst._state
	for idx in range(P.total_briques()):
		BrickField.detruire(s, idx)
	inst.queue_redraw()
	for _i in range(4):
		await process_frame
	var imgB: Image = root.get_texture().get_image()

	var changes := _diff_zone_briques(imgA, imgB)
	var ok := changes > 0
	var fails: Array = []
	if not ok:
		fails.append("aucun pixel de la zone briques n'a change (%d) — fenetre GPU requise (--headless rend une texture nulle)" % changes)
	print("FORGE_ORACLE demo_brick_destruction " + JSON.stringify({"ok": ok, "fails": fails, "data": {"pixels_changes": changes}}))
	quit(0 if ok else 1)
