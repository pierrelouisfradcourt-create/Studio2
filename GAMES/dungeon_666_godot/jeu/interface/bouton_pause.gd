extends Button
## Le bouton pause : un vrai Button (style du thème), dont le pictogramme « deux barres » est
## dessiné. Clic et toucher sont gérés par Button lui-même (vérifié au banc : D666_PAUSE=1).

const BARRE := Vector2(4.0, 14.0)
const ECART := 4.0

func _draw() -> void:
	var c := size / 2.0
	var col := get_theme_color("font_color")
	draw_rect(Rect2(c + Vector2(-ECART / 2.0 - BARRE.x, -BARRE.y / 2.0), BARRE), col)
	draw_rect(Rect2(c + Vector2(ECART / 2.0, -BARRE.y / 2.0), BARRE), col)
