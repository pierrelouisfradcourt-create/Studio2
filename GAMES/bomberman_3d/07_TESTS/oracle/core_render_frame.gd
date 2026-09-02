# core_render_frame.gd — oracle PIXEL de la ligne core.render (proof_kind: pixel).
#
# forge:run_mode = gpu_window
#
# La ligne ci-dessus est la DIRECTIVE STATIQUE lue par le collecteur
# (scripts/forge/product_oracle_godot.py) AVANT execution : elle route ce volet vers une
# fenetre GPU hors ecran au lieu de --headless, ou le driver dummy rend une texture NULLE.
#
# CE QUI EST PROUVE ICI — quatre assertions, et la quatrieme est celle qui compte :
#   1. une image existe, aux dimensions du viewport ;
#   2. elle n'est pas MONOCHROME (quelque chose est reellement rendu) ;
#   3. deux etats de jeu distincts produisent des images DIFFERENTES ;
#   4. la REGION PROJETEE d'une case detruite CHANGE, et une region temoin ou rien ne se
#      passe NE CHANGE PAS. La double assertion est le point : sans le temoin, n'importe
#      quel bruit de rendu ferait passer (3) pour une preuve de causalite.
#
# La projection cellule -> ecran est fournie par la presentation comme fonction pure
# (`projeter`) : l'oracle ne devine jamais ou regarder.
#
# Sortie : "FORGE_ORACLE core_render_frame {json}".
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const View = preload("res://06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")

const FRAMES := 8

var _vue
var _etat_a
var _etat_b
var _cible: Vector2i         # case detruite entre A et B
var _temoin: Vector2i        # case ou rien ne change
var _img_a: Image
var _phase := 0
var _f := 0


func _initialize() -> void:
	get_root().size = Vector2i(800, 600)
	var desc: Dictionary = Content.descripteur(0)
	var carte: Dictionary = Validator.carte_validee(desc)
	_etat_a = State.initial(carte, desc, 1, 4)

	# Etat B : la MEME partie, avec un bloc detruit et une flamme allumee. Deux etats
	# distincts par une difference NOMMEE, pas par une derive de simulation — c'est ce qui
	# rend l'assertion (4) verifiable case par case.
	_etat_b = _etat_a.clone()
	_cible = Vector2i(3, 1)
	_temoin = Vector2i(1, 5)
	_etat_b.arene.detruire(_cible)
	_etat_b.flammes[_cible] = P.DUREE_FLAMME

	_vue = View.new()
	get_root().add_child(_vue)
	_vue.batir(_etat_a)


func _rendre(etat) -> void:
	_vue.rafraichir(etat)


# Deux images different-elles dans une fenetre carree autour d'un point d'ecran ?
func _region_change(a: Image, b: Image, centre: Vector2, demi: int) -> bool:
	if a == null or b == null or centre.x < 0.0:
		return false
	var x0: int = int(max(0, int(centre.x) - demi))
	var y0: int = int(max(0, int(centre.y) - demi))
	var x1: int = int(min(a.get_width() - 1, int(centre.x) + demi))
	var y1: int = int(min(a.get_height() - 1, int(centre.y) + demi))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return true
	return false


func _monochrome(img: Image) -> bool:
	if img == null:
		return true
	var p0 := img.get_pixel(0, 0)
	for x in range(0, img.get_width(), 8):
		for y in range(0, img.get_height(), 8):
			if img.get_pixel(x, y) != p0:
				return false
	return true


func _process(_delta: float) -> bool:
	_f += 1
	if _f < FRAMES:
		return false
	if _phase == 0:
		var t0 := get_root().get_texture()
		_img_a = t0.get_image() if t0 != null else null
		_rendre(_etat_b)
		_phase = 1
		_f = 0
		return false

	var t1 := get_root().get_texture()
	var img_b: Image = t1.get_image() if t1 != null else null

	var fails: Array = []
	var w := 0
	var h := 0
	var p_cible := Vector2(-1, -1)
	var p_temoin := Vector2(-1, -1)

	if _img_a == null or img_b == null:
		fails.append("capture nulle (fenetre GPU absente ?)")
	else:
		w = _img_a.get_width()
		h = _img_a.get_height()
		if _monochrome(_img_a):
			fails.append("image A monochrome (rendu mort)")
		if _img_a.get_data() == img_b.get_data():
			fails.append("deux etats distincts -> images IDENTIQUES")
		p_cible = _vue.projeter(_cible)
		p_temoin = _vue.projeter(_temoin)
		if p_cible.x < 0.0:
			fails.append("la case detruite n'est pas projetable (camera ?)")
		elif not _region_change(_img_a, img_b, p_cible, 12):
			fails.append("la region projetee de la case DETRUITE n'a pas change")
		if p_temoin.x < 0.0:
			fails.append("la case temoin n'est pas projetable (camera ?)")
		elif _region_change(_img_a, img_b, p_temoin, 6):
			fails.append("la region TEMOIN a change alors que rien ne s'y passe (bruit de rendu)")

	print("FORGE_ORACLE core_render_frame " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"viewport": [w, h],
		"case_detruite": [_cible.x, _cible.y], "ecran_detruite": [p_cible.x, p_cible.y],
		"case_temoin": [_temoin.x, _temoin.y], "ecran_temoin": [p_temoin.x, p_temoin.y],
	}))
	quit(0 if fails.is_empty() else 1)
	return true
