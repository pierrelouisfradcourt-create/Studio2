extends Control
## Une pièce dessinée : le losange des Âmes (◆) ou, avec `disque`, la pièce d'or ronde (●) — les
## mêmes signes que dans la Ville. La couleur vient de la palette (posée par le HUD), jamais
## écrite ici ; un liseré sombre la détache du sol.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const LISERE := 1.5

## Vrai : un disque (pièce d'or) au lieu d'un losange.
@export var disque := false

var couleur := Color.WHITE:
	set(v):
		couleur = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size / 2.0
	var d := minf(size.x, size.y) / 2.0
	var encre := Color(Couleurs.UI["void"], 0.85)
	if disque:
		draw_circle(c, d + LISERE, encre, true, -1.0, true)
		draw_circle(c, d, couleur, true, -1.0, true)
		draw_arc(c, d * 0.55, 0.0, TAU, 16, couleur.darkened(0.3), 1.0, true)
		return
	var g := d + LISERE
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0)]), encre)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), couleur)
