extends "res://jeu/monde/calque.gd"
## Les lueurs du sol : flaques de lumière et fissures de lave à la teinte du Cercle, qui
## respirent lentement. Calque en mélange additif (matériau posé dans monde.tscn), sous les murs
## pour l'œil : il reste à l'intérieur de la salle.

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var teinte: Color = monde.teinte_du_cercle()
	var t := temps()
	var decor: Dictionary = monde.decor()
	var room: Dictionary = g.room
	var dedans := Rect2(room.pad, room.pad, room.w - 2.0 * room.pad, room.h - 2.0 * room.pad)
	for f in decor.flaques:
		if dedans.grow(-f.r).has_point(f.p):
			Trace.halo(self, f.p, f.r * 2.0, teinte, 0.1 + 0.03 * sin(t * 1.3 + f.p.x))
	for f in decor.fissures:
		if f.lave and _dans(dedans, f.pts) and _libre(room, f.pts):
			var a := 0.26 + 0.1 * sin(t * 2.0 + f.phase)
			draw_polyline(f.pts, Trace.voile(teinte, a * 0.3), 6.0, true)
			draw_polyline(f.pts, Trace.voile(teinte, a), 2.0, true)

## Une fissure de lave ne court pas sur un pilier (marge : la hauteur dessinée du pilier).
func _libre(room: Dictionary, pts: PackedVector2Array) -> bool:
	for o in room.obstacles:
		var pilier := Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0).grow(16.0)
		for i in pts.size() - 1:
			if pilier.has_point(pts[i]) or pilier.has_point(pts[i + 1]) or pilier.has_point((pts[i] + pts[i + 1]) / 2.0):
				return false
	return true

## Une fissure de lave ne passe pas sous un mur.
func _dans(dedans: Rect2, pts: PackedVector2Array) -> bool:
	for p in pts:
		if not dedans.has_point(p):
			return false
	return true
