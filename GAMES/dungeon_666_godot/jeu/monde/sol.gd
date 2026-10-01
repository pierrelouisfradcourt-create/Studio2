extends "res://jeu/monde/calque.gd"
## Le sol de la salle : dalles teintées par le Cercle, fissures, murs, piliers et leurs ombres.
## Rien ne bouge ici : le calque n'est redessiné que lorsque la salle change. Le sol reste
## discret, c'est le fond sur lequel le danger doit se lire.

const DALLE := 88.0
const JOINT := 1.5
const BISEAU := 3.0
const GRAINS := 5
const TEINTE_DU_CERCLE := 0.05 # part de la teinte du Cercle dans la pierre
const MUR_DEBORD := 1200.0 # u de mur peintes autour de la salle (la caméra peut déborder)
const MUR_CRETE := 7.0 # u : crête claire du mur, côté salle
const OMBRE_DU_MUR := 22.0
const HAUTEUR_PILIER := 14.0 # hauteur apparente (fausse 3D vue de dessus)
const PIERRES: Array[Color] = [Color("#1b1116"), Color("#22151b"), Color("#1e1318"), Color("#24171d")]

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
	var alea := RandomNumberGenerator.new()
	alea.seed = 7
	draw_rect(Rect2(0, 0, room.w, room.h), PAL.crack)
	_dalles(room, monde.teinte_du_cercle(), alea)
	for f in monde.decor().fissures:
		if not f.lave:
			draw_polyline(f.pts, PAL.crack, 3.0, true)
	_murs(room)
	for o in room.obstacles:
		_ombre_pilier(o)
	for o in room.obstacles:
		_pilier(o)

func _dalles(room: Dictionary, teinte: Color, alea: RandomNumberGenerator) -> void:
	var colonnes := int(ceil(room.w / DALLE))
	var rangs := int(ceil(room.h / DALLE))
	for i in colonnes:
		for j in rangs:
			_dalle(Vector2(i, j) * DALLE + Vector2(JOINT, JOINT), teinte, alea)

## Une dalle : pierre, biseau discret (lumière en haut à gauche), grain.
func _dalle(coin: Vector2, teinte: Color, alea: RandomNumberGenerator) -> void:
	var c := DALLE - 2.0 * JOINT
	var pierre: Color = PIERRES[alea.randi() % PIERRES.size()].lerp(teinte, TEINTE_DU_CERCLE)
	draw_rect(Rect2(coin, Vector2(c, c)), pierre)
	var clair := Color(1.0, 0.86, 0.78, 0.035)
	var sombre := Color(0, 0, 0, 0.18)
	draw_rect(Rect2(coin, Vector2(c, BISEAU)), clair)
	draw_rect(Rect2(coin, Vector2(BISEAU, c)), clair)
	draw_rect(Rect2(coin + Vector2(0, c - BISEAU), Vector2(c, BISEAU)), sombre)
	draw_rect(Rect2(coin + Vector2(c - BISEAU, 0), Vector2(BISEAU, c)), sombre)
	for k in GRAINS:
		var grain := Color(0, 0, 0, 0.12) if alea.randf() < 0.5 else Color(1, 1, 1, 0.025)
		var p := coin + Vector2(alea.randf(), alea.randf()) * (c - 6.0)
		draw_rect(Rect2(p, Vector2(2.0 + alea.randf() * 3.0, 2.0 + alea.randf() * 3.0)), grain)

## Murs : masse sombre autour de la salle, crête claire côté salle, ombre portée vers l'intérieur.
func _murs(room: Dictionary) -> void:
	var p: float = room.pad
	var d := MUR_DEBORD
	var dedans := Rect2(p, p, room.w - 2.0 * p, room.h - 2.0 * p)
	draw_rect(Rect2(-d, -d, room.w + 2.0 * d, d + p), PAL.wall)
	draw_rect(Rect2(-d, room.h - p, room.w + 2.0 * d, d + p), PAL.wall)
	draw_rect(Rect2(-d, 0, d + p, room.h), PAL.wall)
	draw_rect(Rect2(room.w - p, 0, d + p, room.h), PAL.wall)
	var ombre := Color(0, 0, 0, 0.42)
	var rien := Color(0, 0, 0, 0)
	Trace.degrade_vertical(self, Rect2(dedans.position, Vector2(dedans.size.x, OMBRE_DU_MUR)), ombre, rien)
	Trace.degrade_horizontal(self, Rect2(dedans.position, Vector2(OMBRE_DU_MUR * 0.6, dedans.size.y)), Color(0, 0, 0, 0.25), rien)
	var crete := dedans.grow(MUR_CRETE / 2.0)
	draw_rect(crete, PAL.wallTop, false, MUR_CRETE)
	draw_rect(dedans.grow(MUR_CRETE), Trace.CERNE, false, 1.5)
	draw_rect(dedans, PAL.wallEdge, false, 2.0)

func _ombre_pilier(o: Dictionary) -> void:
	draw_rect(Rect2(o.x0 + 7.0, o.y0 + 9.0, o.x1 - o.x0, o.y1 - o.y0), PAL.shadow)

## Pilier avec son volume : flanc sombre au pied, dessus clair décalé vers le haut, cerne sombre.
func _pilier(o: Dictionary) -> void:
	var taille := Vector2(o.x1 - o.x0, o.y1 - o.y0)
	var dessus := Rect2(Vector2(o.x0, o.y0 - HAUTEUR_PILIER), taille)
	draw_rect(Rect2(Vector2(o.x0, o.y0), taille), PAL.pillarSide)
	draw_rect(dessus, PAL.pillarTop)
	draw_rect(Rect2(dessus.position, Vector2(taille.x, BISEAU)), Color(1.0, 0.86, 0.78, 0.07))
	draw_rect(Rect2(dessus.position, Vector2(BISEAU, taille.y)), Color(1.0, 0.86, 0.78, 0.05))
	draw_line(Vector2(o.x0, dessus.end.y), Vector2(o.x1, dessus.end.y), PAL.wallEdge, 2.0)
	draw_rect(dessus, PAL.wallEdge, false, 1.5)
	draw_rect(Rect2(dessus.position, taille + Vector2(0, HAUTEUR_PILIER)), Trace.CERNE, false, 2.0)
