# core_render_frame.gd — oracle de la ligne core.render. FENETRE GPU REELLE (jamais
# --headless : le driver dummy rend une texture nulle). Rend DEUX etats distincts (positions
# de tete differentes) via le meme grid_view que le produit et asserte que les deux images
# DIFFERENT et ne sont pas monochromes. Sortie : "FORGE_ORACLE core_render_frame {json}".
#
# forge:run_mode = gpu_window
#
# La ligne ci-dessus est la DIRECTIVE STATIQUE lue par le collecteur
# (scripts/forge/product_oracle_godot.py) AVANT toute execution : elle route ce volet
# vers un lancement en fenetre GPU hors ecran au lieu de --headless. Elle est statique
# par necessite mesuree (2026-08-10, meme binaire, meme volet) :
#     fenetre GPU -> {"ok": true,  "fails": []}                       exit 0
#     --headless  -> {"ok": false, "fails": ["capture nulle (...)"]}  exit 1
# Lire le mode APRES execution reviendrait a le lire apres avoir deja fabrique le rouge.
# Aucun comportement de ce volet n'est modifie par cette ligne.
extends SceneTree

const GV = preload("res://06_RUNTIME/adapters/presentation/grid_view.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const CELL_PX := 24

var _phase := 0
var _f := 0
var _a
var _b
var _img_a: Image
var _img_b: Image

func _initialize() -> void:
	var cote: int = P.TAILLE_GRILLE * CELL_PX
	get_root().size = Vector2i(cote, cote)
	_a = State.initial(2)
	_b = _a.clone()
	for i in range(6):
		_b = Loop.step(_b, Loop.AUCUNE)["etat"]
	_rendre(_a)

func _rendre(state) -> void:
	for c in get_root().get_children():
		if c is ColorRect:
			c.queue_free()
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			var rect := ColorRect.new()
			rect.color = GV.couleur(GV.categorie_cellule(state, Vector2i(x, y)))
			rect.position = Vector2(x * CELL_PX, y * CELL_PX)
			rect.size = Vector2(CELL_PX, CELL_PX)
			get_root().add_child(rect)

func _monochrome(img: Image) -> bool:
	var p0 := img.get_pixel(0, 0)
	for x in range(0, img.get_width(), 16):
		for y in range(0, img.get_height(), 16):
			if img.get_pixel(x, y) != p0:
				return false
	return true

func _process(_delta: float) -> bool:
	_f += 1
	if _f < 8:
		return false
	if _phase == 0:
		_img_a = get_root().get_texture().get_image()
		_rendre(_b)
		_phase = 1
		_f = 0
		return false
	_img_b = get_root().get_texture().get_image()
	var fails: Array = []
	if _img_a == null or _img_b == null:
		fails.append("capture nulle (fenetre GPU absente ?)")
	else:
		if _monochrome(_img_a):
			fails.append("image A monochrome (rendu mort)")
		if _img_a.get_data() == _img_b.get_data():
			fails.append("deux etats distincts -> images identiques")
	print("FORGE_ORACLE core_render_frame " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"tete_a": [_a.segments[0].x, _a.segments[0].y],
		"tete_b": [_b.segments[0].x, _b.segments[0].y],
	}))
	quit(0 if fails.is_empty() else 1)
	return true
