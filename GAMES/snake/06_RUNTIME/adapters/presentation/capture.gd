# capture.gd — ligne proof.visual_gpu_window. Preuve VISUELLE : lance en FENETRE GPU REELLE
# (--rendering-driver vulkan, fenetre hors ecran), rend deux etats DISTINCTS via le meme
# grid_view que le produit, et sauvegarde deux PNG NON VIDES et DIFFERENTS. Interdit en
# --headless (le driver dummy rend une texture nulle : aucun PNG valide — memoire Forge
# 2026-07-22). SceneTree. Aucun litteral de GAMEPLAY ici (dimensions de grille lues dans
# params) ; CELL_PX est une valeur de PRESENTATION.
extends SceneTree

const GV = preload("res://06_RUNTIME/adapters/presentation/grid_view.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const CELL_PX := 24  # taille de rendu d'une case (presentation, pas gameplay)
const PNG_A := "user://snake_capture_a.png"
const PNG_B := "user://snake_capture_b.png"

var _phase := 0
var _f := 0
var _etat_a
var _etat_b
var _img_a: Image
var _img_b: Image

func _initialize() -> void:
	var cote: int = P.TAILLE_GRILLE * CELL_PX
	get_root().size = Vector2i(cote, cote)
	_etat_a = State.initial(1)
	# Etat B : quelques ticks plus tard -> position de tete DIFFERENTE (image distincte).
	_etat_b = _etat_a.clone()
	for i in range(4):
		_etat_b = Loop.step(_etat_b, Loop.AUCUNE)["etat"]
	_rendre(_etat_a)

# Purge les cellules puis rend l'etat en ColorRect (rendu par le compositeur GPU reel).
func _rendre(state) -> void:
	for c in get_root().get_children():
		if c is ColorRect:
			c.queue_free()
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			var cat := GV.categorie_cellule(state, Vector2i(x, y))
			var rect := ColorRect.new()
			rect.color = GV.couleur(cat)
			rect.position = Vector2(x * CELL_PX, y * CELL_PX)
			rect.size = Vector2(CELL_PX, CELL_PX)
			get_root().add_child(rect)

func _process(_delta: float) -> bool:
	_f += 1
	if _f < 8:
		return false
	if _phase == 0:
		_img_a = get_root().get_texture().get_image()
		_img_a.save_png(PNG_A)
		_rendre(_etat_b)
		_phase = 1
		_f = 0
		return false
	# phase 1
	_img_b = get_root().get_texture().get_image()
	_img_b.save_png(PNG_B)
	_conclure()
	return true

func _conclure() -> void:
	var fails: Array = []
	var taille_a := _fichier_taille(PNG_A)
	var taille_b := _fichier_taille(PNG_B)
	var pngs_non_vides := 0
	if taille_a > 0:
		pngs_non_vides += 1
	else:
		fails.append("PNG A vide/absent")
	if taille_b > 0:
		pngs_non_vides += 1
	else:
		fails.append("PNG B vide/absent")
	# Non-monochrome (une image toute d'une couleur = rendu mort).
	if _img_a != null and _monochrome(_img_a):
		fails.append("PNG A monochrome (rendu mort)")
	# Deux etats distincts -> deux images differentes.
	if _img_a != null and _img_b != null and _img_a.get_data() == _img_b.get_data():
		fails.append("les deux captures sont identiques (etats non distincts a l'ecran)")
	print("FORGE_ORACLE visual_gpu_window " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"pngs_non_vides": pngs_non_vides,
		"taille_a": taille_a, "taille_b": taille_b,
		"png_a": ProjectSettings.globalize_path(PNG_A),
		"png_b": ProjectSettings.globalize_path(PNG_B),
	}))
	quit(0 if fails.is_empty() else 1)

func _fichier_taille(chemin: String) -> int:
	if not FileAccess.file_exists(chemin):
		return 0
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return int(n)

func _monochrome(img: Image) -> bool:
	var p0 := img.get_pixel(0, 0)
	for x in range(0, img.get_width(), 16):
		for y in range(0, img.get_height(), 16):
			if img.get_pixel(x, y) != p0:
				return false
	return true
