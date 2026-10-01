extends Control
## Un losange plein : la pièce d'or, la gemme des Âmes. La couleur vient de la palette (posée
## par le HUD), jamais écrite ici.

var couleur := Color.WHITE:
	set(v):
		couleur = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size / 2.0
	var d := minf(size.x, size.y) / 2.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), couleur)
