extends "res://jeu/monde/calque.gd"
## Les bords seuls des dangers, retracés AU-DESSUS du héros et des ennemis : dans une mêlée, la
## limite d'une frappe reste lisible. Seulement ce qui fait mal (rouge) ; les alertes
## inoffensives restent au sol.

const LARGEUR := 2.5

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	for h in g.hazards:
		if D6Js.truthy(h.get("hitsPlayer")) and not D6Js.truthy(h.get("done")):
			_zone(h)
	for e in g.enemies:
		var t = e.get("tele")
		if t is Dictionary and not D6Js.truthy(e.get("dead")) and not D6Js.truthy(t.get("harmless")):
			_telegraphe(partie.position_dessin(e), t)

func _zone(h: Dictionary) -> void:
	var p := Vector2(h.x, h.y)
	if h.shape == "line":
		Trace.contour(self, Trace.bande(p, h.angle, h.length, h.width), PAL.danger, LARGEUR)
		return
	draw_circle(p, h.r, PAL.danger, false, LARGEUR, true)
	if h.shape == "ring" and float(h.get("inner", 0.0)) > 0.0:
		draw_circle(p, h.inner, PAL.danger, false, LARGEUR, true)

func _telegraphe(p: Vector2, t: Dictionary) -> void:
	if t.shape == "cone":
		draw_polyline(Trace.arc(p, t["range"], t.angle - t.arc / 2.0, t.angle + t.arc / 2.0), PAL.danger, LARGEUR, true)
	elif t.shape == "line":
		Trace.contour(self, Trace.bande(p, t.angle, t.length, t.width), PAL.danger, LARGEUR)
	else:
		draw_circle(p, t.r, PAL.danger, false, LARGEUR, true)
