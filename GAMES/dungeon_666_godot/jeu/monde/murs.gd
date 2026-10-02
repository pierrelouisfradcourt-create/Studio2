extends "res://jeu/monde/calque.gd"
## Les murs d'enceinte et l'ombre des piliers. La salle est vue comme une fosse : la face
## intérieure de chaque mur s'évase vers l'extérieur (claire au fond, sombre sur les côtés et
## devant), coiffée d'un dessus de pierre à l'arête claire. Les piliers, eux, sont DEBOUT : ils
## sont dessinés par piliers.gd, triés en profondeur avec les créatures ; seule leur ombre portée
## douce reste ici, au sol. Rien ne bouge ici : le calque n'est redessiné que lorsque la salle
## change (les flammes des flambeaux sont dans lueurs.gd).
##
## Coût : tout est tracé en rectangles puis en primitives (quadrilatères, traits non lissés,
## tous d'équerre), pour partir en quelques lots au lieu d'un appel de dessin par forme.

const BRIQUE := 68.0 # u : longueur d'une pierre de parement
const RANGS := 3 # assises visibles sur une face
const OMBRE_PILIER := Vector2(10.0, 14.0) # décalage de l'ombre portée (lumière en haut à gauche)
const OMBRE_FLOU := 18.0
const NUIT := 70.0 # u : fondu du dessus des murs vers le vide
const FER := Color("#1a1216")

var _salle = null

func _process(_delta: float) -> void:
	var g = etat()
	if g != null and not is_same(g.room, _salle):
		_salle = g.room
		queue_redraw()

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var room: Dictionary = g.room
	var a: Dictionary = monde.ambiance()
	var d := dedans(room)
	var haut := Rect2(d.position - Vector2(FACE_COTE, FACE_NORD), d.size + Vector2(2.0 * FACE_COTE, FACE_NORD + FACE_SUD))
	# 1. rectangles : le dessus des murs.
	_dessus(haut, Ambiance.eclaire(a.mur, 1.12))
	# 2. primitives : fondu vers le vide, faces, joints, arêtes, ombres des piliers.
	_nuit(haut.grow(DESSUS), Ambiance.eclaire(a.mur, 0.3))
	_faces(d, haut, a.mur)
	_parement(d, haut, Trace.voile(a.joint, 0.55))
	_aretes(d, haut, a)
	for o in room.obstacles:
		_ombre_pilier(o)
	for f in monde.flambeaux():
		_applique(f.p)

func _coins(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([ca, cb, cc, cd]), PackedVector2Array())

## Cadre d'un rectangle, en quatre traits d'équerre.
func _cadre(r: Rect2, couleur: Color, largeur: float) -> void:
	Trace.cadre(self, r, couleur, largeur)

## Le dessus des murs : un cadre de pierre autour de la fosse.
func _dessus(haut: Rect2, pierre: Color) -> void:
	var dehors := haut.grow(DESSUS)
	draw_rect(Rect2(dehors.position, Vector2(dehors.size.x, DESSUS)), pierre)
	draw_rect(Rect2(dehors.position.x, haut.end.y, dehors.size.x, DESSUS), pierre)
	draw_rect(Rect2(dehors.position.x, haut.position.y, DESSUS, haut.size.y), pierre)
	draw_rect(Rect2(haut.end.x, haut.position.y, DESSUS, haut.size.y), pierre)

## Au-delà des murs : la pierre se perd dans le vide.
func _nuit(dehors: Rect2, loin: Color) -> void:
	var i := _coins(dehors)
	var o := _coins(dehors.grow(NUIT))
	var vide: Color = PAL["void"]
	for k in 4:
		var n := (k + 1) % 4
		_quad(i[k], i[n], o[n], o[k], loin, loin, vide, vide)

## Les quatre faces intérieures, en trapèzes : celle du fond prend la lumière, celle de devant
## reste dans l'ombre. Chaque face est plus sombre à son pied.
func _faces(d: Rect2, haut: Rect2, mur: Color) -> void:
	var i := _coins(d)
	var o := _coins(haut)
	var pieds := [0.46, 0.3, 0.22, 0.36] # fond, droite, devant, gauche
	var cretes := [0.98, 0.62, 0.46, 0.74]
	for k in 4:
		var n := (k + 1) % 4
		var sombre: Color = Ambiance.eclaire(mur, pieds[k])
		var clair: Color = Ambiance.eclaire(mur, cretes[k])
		_quad(i[k], i[n], o[n], o[k], sombre, sombre, clair, clair)

## Assises et joints des quatre faces, joints du dessus.
func _parement(d: Rect2, haut: Rect2, joint: Color) -> void:
	var dehors := haut.grow(DESSUS)
	for rang in range(1, RANGS + 1):
		var t := float(rang) / float(RANGS)
		var t0 := float(rang - 1) / float(RANGS)
		if rang < RANGS:
			_cadre(Rect2(d.position - Vector2(FACE_COTE, FACE_NORD) * t, d.size + Vector2(2.0 * FACE_COTE, FACE_NORD + FACE_SUD) * t), joint, 1.5)
		var decalage := BRIQUE * 0.5 * float(rang % 2)
		var x := d.position.x + decalage
		while x < d.end.x:
			draw_line(Vector2(x, d.position.y - FACE_NORD * t0), Vector2(x, d.position.y - FACE_NORD * t), joint, 1.5)
			draw_line(Vector2(x, d.end.y + FACE_SUD * t0), Vector2(x, d.end.y + FACE_SUD * t), joint, 1.5)
			x += BRIQUE
		var y := d.position.y + decalage
		while y < d.end.y:
			draw_line(Vector2(d.position.x - FACE_COTE * t0, y), Vector2(d.position.x - FACE_COTE * t, y), joint, 1.5)
			draw_line(Vector2(d.end.x + FACE_COTE * t0, y), Vector2(d.end.x + FACE_COTE * t, y), joint, 1.5)
			y += BRIQUE
	var xd := haut.position.x + BRIQUE * 0.5
	while xd < haut.end.x:
		draw_line(Vector2(xd, dehors.position.y), Vector2(xd, haut.position.y), joint, 1.5)
		draw_line(Vector2(xd + BRIQUE * 0.5, haut.end.y), Vector2(xd + BRIQUE * 0.5, dehors.end.y), joint, 1.5)
		xd += BRIQUE
	var yd := haut.position.y + BRIQUE * 0.5
	while yd < haut.end.y:
		draw_line(Vector2(dehors.position.x, yd), Vector2(haut.position.x, yd), joint, 1.5)
		draw_line(Vector2(haut.end.x, yd + BRIQUE * 0.5), Vector2(dehors.end.x, yd + BRIQUE * 0.5), joint, 1.5)
		yd += BRIQUE

## Les arêtes : cerne au pied des murs, arête claire en haut des faces (un rien de la teinte du
## Cercle), cerne au bord extérieur, et les quatre arêtes d'angle de la fosse.
func _aretes(d: Rect2, haut: Rect2, a: Dictionary) -> void:
	var claire: Color = Ambiance.eclaire(a.mur, 1.9).lerp(a.teinte, 0.18)
	var i := _coins(d)
	var o := _coins(haut)
	for k in 4:
		draw_line(i[k], o[k], Trace.voile(Trace.CERNE, 0.6), 1.5, true)
	_cadre(haut.grow(3.0), Ambiance.eclaire(a.mur, 1.4), 6.0)
	_cadre(d, Trace.CERNE, 2.5)
	_cadre(haut, claire, 2.0)
	_cadre(haut.grow(DESSUS), Trace.voile(Trace.CERNE, 0.9), 3.0)

## Ombre portée douce d'un pilier : un cœur sombre et un bord qui s'estompe.
func _ombre_pilier(o: Dictionary) -> void:
	var r := Rect2(Vector2(o.x0, o.y0) + OMBRE_PILIER, Vector2(o.x1 - o.x0, o.y1 - o.y0)).grow(-4.0)
	var i := _coins(r)
	var e := _coins(r.grow(OMBRE_FLOU))
	var ombre := Color(0, 0, 0, 0.6)
	var rien := Color(0, 0, 0, 0)
	_quad(i[0], i[1], i[2], i[3], ombre, ombre, ombre, ombre)
	for k in 4:
		var n := (k + 1) % 4
		_quad(i[k], i[n], e[n], e[k], ombre, ombre, rien, rien)

## Applique de fer d'un flambeau, scellée dans le mur (la flamme est dessinée par lueurs.gd).
func _applique(p: Vector2) -> void:
	draw_line(p, p + Vector2(0, 13.0), FER, 4.0)
	_quad(p + Vector2(-8, -3), p + Vector2(8, -3), p + Vector2(5, 5), p + Vector2(-5, 5), FER, FER, FER, FER)
	draw_line(p + Vector2(-8, -3), p + Vector2(8, -3), Color("#6a5a52"), 1.5)
