extends Control
## Un filet d'ornement : un trait fin qui s'efface vers ses deux bouts, un losange au milieu.
## Sépare un grand titre de ce qui le suit (logo, bannières du HUD, écran de mort). Dessiné,
## aucune image ; sa couleur vient de la palette, posée par la vue (`couleur`).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const HAUTEUR := 9.0
const LOSANGE := 3.5 # demi-diagonale
const ECART := 9.0 # vide entre le losange et le trait

## Couleur du filet (par défaut : l'or de l'interface).
var couleur: Color = Couleurs.UI.gold:
	set(v):
		couleur = v
		queue_redraw()
## Largeur maximale du filet (px) ; au-delà, il reste centré.
@export var largeur_max := 320.0
@export var epaisseur := 1.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = HAUTEUR
	resized.connect(queue_redraw)

func _draw() -> void:
	var c := size / 2.0
	var demi := minf(size.x, largeur_max) / 2.0
	var plein := couleur
	var vide := Color(couleur, 0.0)
	for sens: float in [-1.0, 1.0]:
		var dedans := c + Vector2(sens * ECART, 0.0)
		var dehors := c + Vector2(sens * demi, 0.0)
		draw_polyline_colors(PackedVector2Array([dedans, dehors]), PackedColorArray([plein, vide]), epaisseur, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -LOSANGE), c + Vector2(LOSANGE, 0), c + Vector2(0, LOSANGE), c + Vector2(-LOSANGE, 0)]), plein)
