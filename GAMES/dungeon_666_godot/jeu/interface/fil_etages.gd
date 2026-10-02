extends Control
## Le fil de la section : une pastille par étage (fait, en cours, à venir), le Gardien au bout,
## plus gros et rouge. Portage des pastilles de `drawTopCenter` (src/render/hud.mjs).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const PAS := 16.0 # écart entre deux pastilles (réduit si la place manque)
const RAYON := 3.5
const RAYON_GARDIEN := 5.0
const HAUTEUR := 14.0
const BATTEMENT := 4.0 # rad/s : la pastille en cours respire

var _index := 1
var _nombre := 18
var _temps := 0.0
var _lot := Triangles.new() # toutes les pastilles en un appel de dessin

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dimensionner()

func poser(index: float, nombre: float) -> void:
	if int(index) == _index and int(nombre) == _nombre:
		return
	_index = int(index)
	_nombre = maxi(1, int(nombre))
	_dimensionner()
	queue_redraw()

func _dimensionner() -> void:
	custom_minimum_size = Vector2((_nombre - 1) * PAS + 2.0 * RAYON_GARDIEN + 4.0, HAUTEUR)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_temps += delta
		queue_redraw()

func _draw() -> void:
	var pal: Dictionary = Couleurs.PAL
	var pas := minf(PAS, (size.x - 2.0 * RAYON_GARDIEN - 4.0) / maxf(1.0, _nombre - 1.0))
	var x0 := size.x / 2.0 - (_nombre - 1) * pas / 2.0
	var y := size.y / 2.0
	for i in range(1, _nombre + 1):
		var c := Vector2(x0 + (i - 1) * pas, y)
		var fait := i < _index
		var ici := i == _index
		var gardien := i == _nombre
		var col: Color = pal.wallEdge
		if gardien:
			col = pal.danger if (fait or ici) else Color(pal.danger).darkened(0.6)
		elif fait:
			col = pal.text
		elif ici:
			col = pal.gold
		if ici:
			var souffle := 0.5 + 0.5 * sin(_temps * BATTEMENT)
			_lot.arc(c, (RAYON_GARDIEN if gardien else RAYON) + 2.5 + souffle, 0.0, TAU, 20, Color(col, 0.55), 1.5)
		_lot.disque(c, RAYON_GARDIEN if gardien else RAYON, col)
	_lot.tracer(self)
