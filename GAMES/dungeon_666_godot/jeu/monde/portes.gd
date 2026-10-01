extends "res://jeu/monde/calque.gd"
## Les portes de la salle : une arche par porte, fermée (herse) ou ouverte (lumière à la couleur
## de la récompense), son icône et son libellé. La porte « town » est le portail de la Ville.

const Icones = preload("res://jeu/monde/icones.gd")
const FOND := Color("#0a0508")
const HERSE := Color("#3a2a30")
const CALMES := {"treasure": Color("#ffb43c"), "rest": Color("#6dd8ff")}
const VOUTE_RETRAIT := 20.0 # u : le centre de la voûte est remonté d'autant
const TRANCHES := 12

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	for d in g.room.doors:
		_porte(d)

func _porte(d: Dictionary) -> void:
	var ouverte := D6Js.truthy(d.get("open"))
	var couleur := couleur_de(d)
	var arche := _arche(d)
	var cx: float = d.x + d.w / 2.0
	var bas: float = d.y + d.h
	draw_colored_polygon(arche, FOND)
	if ouverte:
		_lumiere(d, couleur)
		if d.reward == "town":
			_portail(Vector2(cx, bas - d.h * 0.5), couleur)
	else:
		_herse(d)
	draw_polyline(arche, Trace.CERNE, 7.0, true)
	draw_polyline(arche, couleur if ouverte else PAL.wallEdge, 3.5, true)
	if ouverte:
		draw_line(Vector2(d.x, bas), Vector2(d.x + d.w, bas), Trace.voile(couleur, 0.5 + 0.2 * sin(temps() * 4.0)), 2.0, true)
	var saut := sin(temps() * 3.0) * 2.0
	Icones.recompense(self, str(d.reward), Vector2(cx, bas + 26.0 + saut), 13.0, couleur if ouverte else PAL.textDim)
	Trace.texte(self, Vector2(cx, bas + 50.0), libelle_de(d), 14, couleur if ouverte else PAL.textDim)

## Couleur de la récompense annoncée (une bénédiction prend celle de sa famille).
static func couleur_de(d: Dictionary) -> Color:
	var famille = d.get("family")
	if d.reward == "boon" and famille != null:
		return Color(D6Data.tables().boons.FAMILIES[famille].color)
	if Couleurs.REWARD_COLORS.has(d.reward):
		return Couleurs.REWARD_COLORS[d.reward]
	return CALMES.get(d.reward, Color.WHITE)

static func libelle_de(d: Dictionary) -> String:
	var famille = d.get("family")
	if d.reward == "boon" and famille != null:
		return D6Data.tables().boons.FAMILIES[famille].name
	return str(D6Data.tables().run.REWARD_LABELS.get(d.reward, ""))

## Tracé ouvert de l'arche : pied gauche, voûte, pied droit.
func _arche(d: Dictionary) -> PackedVector2Array:
	var r: float = d.w / 2.0
	var centre := Vector2(d.x + r, d.y + r - VOUTE_RETRAIT)
	var pts := PackedVector2Array([Vector2(d.x, d.y + d.h)])
	pts.append_array(Trace.arc(centre, r, PI, TAU, 20))
	pts.append(Vector2(d.x + d.w, d.y + d.h))
	return pts

## Demi-largeur de l'arche à la hauteur y.
func _demi_largeur(d: Dictionary, y: float) -> float:
	var r: float = d.w / 2.0
	var cy: float = d.y + r - VOUTE_RETRAIT
	if y >= cy:
		return r
	return sqrt(maxf(0.0, r * r - (cy - y) * (cy - y)))

## Porte ouverte : halo au seuil et lumière qui monte dans l'arche (transparente en haut).
func _lumiere(d: Dictionary, couleur: Color) -> void:
	var t := temps()
	var cx: float = d.x + d.w / 2.0
	var haut: float = d.y + d.w / 2.0 - VOUTE_RETRAIT - d.w / 2.0
	var bas: float = d.y + d.h
	var force := 0.5 + 0.1 * sin(t * 3.0)
	for i in TRANCHES:
		var k0 := float(i) / float(TRANCHES)
		var k1 := float(i + 1) / float(TRANCHES)
		var y0 := lerpf(haut, bas, k0)
		var y1 := lerpf(haut, bas, k1)
		var l0 := _demi_largeur(d, y0)
		var l1 := _demi_largeur(d, y1)
		var pts := PackedVector2Array([Vector2(cx - l0, y0), Vector2(cx + l0, y0), Vector2(cx + l1, y1), Vector2(cx - l1, y1)])
		var c0 := Trace.voile(couleur, force * k0)
		var c1 := Trace.voile(couleur, force * k1)
		draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
	Trace.halo(self, Vector2(cx, bas - 10.0), 90.0, couleur, 0.35 + 0.1 * sin(t * 4.0))

## Porte fermée : herse de barreaux sous la voûte.
func _herse(d: Dictionary) -> void:
	var r: float = d.w / 2.0
	var cx: float = d.x + r
	var cy: float = d.y + r - VOUTE_RETRAIT
	var x: float = d.x + 15.0
	while x < d.x + d.w - 4.0:
		var haut := cy - sqrt(maxf(0.0, r * r - (x - cx) * (x - cx)))
		draw_line(Vector2(x, haut), Vector2(x, d.y + d.h), HERSE, 4.0, true)
		x += 18.0
	draw_line(Vector2(d.x, d.y + d.h * 0.45), Vector2(d.x + d.w, d.y + d.h * 0.45), HERSE, 4.0, true)

## Portail de la Ville : anneaux qui tournent dans l'arche.
func _portail(p: Vector2, couleur: Color) -> void:
	var t := temps()
	Trace.halo(self, p, 46.0, couleur, 0.55)
	for i in 3:
		var r := 30.0 - 9.0 * float(i)
		var a := t * (1.6 + 0.7 * float(i)) * (1.0 if i % 2 == 0 else -1.0)
		draw_arc(p, r, a, a + 4.2, 24, Trace.voile(couleur, 0.9 - 0.2 * float(i)), 3.0, true)
	draw_circle(p, 5.0 + sin(t * 5.0), Color.WHITE, true, -1.0, true)
