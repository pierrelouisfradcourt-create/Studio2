extends Control
## Les bénédictions actives du run : un losange par bénédiction, de la couleur de sa famille
## (le péché) ; une bénédiction DUO porte ses deux couleurs. Les losanges passent à la ligne
## quand la largeur manque. Tables lues dans D6Data.tables().boons, jamais recopiées.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAS := 16.0
const DEMI := 6.0 # demi-diagonale d'un losange
const LIGNE := 16.0

var _couleurs: Array = [] # par bénédiction : [Color] ou [Color, Color] (duo)
var _cle := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_dimensionner)

func poser(boons: Array) -> void:
	var cle := ""
	for b in boons:
		cle += str(b.id) + ";"
	if cle == _cle:
		return
	_cle = cle
	_couleurs.clear()
	for b in boons:
		_couleurs.append(_couleurs_de(b.id))
	_dimensionner()
	queue_redraw()

func _couleurs_de(id) -> Array:
	var familles: Dictionary = D6Data.tables().boons.FAMILIES
	var def = D6Boons.boon_def(id)
	var noms: Array = []
	if def is Dictionary:
		noms = def.get("families", [def.get("family")])
	var out: Array = []
	for n in noms:
		if familles.has(n):
			out.append(Color(String(familles[n].color)))
	return out if not out.is_empty() else [Couleurs.PAL.text]

func _par_ligne() -> int:
	return maxi(1, int(floorf(maxf(PAS, size.x) / PAS)))

func _dimensionner() -> void:
	var lignes := ceili(float(_couleurs.size()) / _par_ligne())
	custom_minimum_size.y = lignes * LIGNE

func _draw() -> void:
	var n := _par_ligne()
	for i in range(_couleurs.size()):
		var c := Vector2((i % n) * PAS + DEMI + 1.0, (i / n) * LIGNE + LIGNE / 2.0)
		var cols: Array = _couleurs[i]
		var haut := c + Vector2(0.0, -DEMI)
		var bas := c + Vector2(0.0, DEMI)
		var contour := PackedVector2Array([haut, c + Vector2(DEMI, 0.0), bas, c + Vector2(-DEMI, 0.0), haut])
		draw_colored_polygon(PackedVector2Array([haut, bas, c + Vector2(-DEMI, 0.0)]), cols[0])
		draw_colored_polygon(PackedVector2Array([haut, c + Vector2(DEMI, 0.0), bas]), cols[cols.size() - 1])
		draw_polyline(contour, Color(Couleurs.UI["void"], 0.85), 1.5, true)
