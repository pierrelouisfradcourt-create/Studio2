extends RefCounted
## Pinceau des créatures : les formes de base, nettes (anticrénelées) et cernées d'un même trait
## sombre. Il dessine sur le CanvasItem qu'on lui donne, PENDANT le `_draw` de celui-ci.
## `alpha` s'applique à tout ce qui est dessiné ensuite (apparition, clignotement, filigrane).

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ENCRE: Color = Couleurs.PAL.enemyOutline
const SANS := Color(0.0, 0.0, 0.0, 0.0) # « pas de contour »
const TRAIT := 2.5

static var _halo: Texture2D = null
static var _ombre: Texture2D = null
static var _police: Font = null

var ci: CanvasItem
var alpha := 1.0

func _init(p_ci: CanvasItem) -> void:
	ci = p_ci

func t(couleur: Color, force: float = 1.0) -> Color:
	return Color(couleur.r, couleur.g, couleur.b, couleur.a * alpha * force)

## Repère de dessin (position, rotation, écrasement) pour tout ce qui suit.
func poser(m: Transform2D) -> void:
	ci.draw_set_transform_matrix(m)

func lever() -> void:
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ------------------------------------------------------------------ points

static func pts_arc(centre: Vector2, r: float, a0: float, a1: float, n: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(centre + Vector2.from_angle(lerpf(a0, a1, float(i) / n)) * r)
	return pts

static func pts_ellipse(centre: Vector2, rx: float, ry: float, angle: float = 0.0, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	return pts

# ------------------------------------------------------------------ formes pleines

func disque(centre: Vector2, r: float, fond: Color, contour: Color = ENCRE, ep: float = TRAIT) -> void:
	ci.draw_circle(centre, r, t(fond), true, -1.0, true)
	if contour.a > 0.0:
		ci.draw_circle(centre, r, t(contour), false, ep, true)

## Polygone plein, bord lissé par son contour (ou par un filet de sa propre couleur).
func forme(pts: PackedVector2Array, fond: Color, contour: Color = ENCRE, ep: float = TRAIT) -> void:
	ci.draw_colored_polygon(pts, t(fond))
	var bord := pts.duplicate()
	bord.append(pts[0])
	if contour.a > 0.0:
		if alpha >= 1.0 and contour.a >= 1.0:
			bord.append(pts[1])
		ci.draw_polyline(bord, t(contour), ep, true)
	elif alpha >= 1.0 and fond.a >= 1.0:
		ci.draw_polyline(bord, fond, 1.0, true)

func ellipse(centre: Vector2, rx: float, ry: float, fond: Color, contour: Color = ENCRE, ep: float = TRAIT, angle: float = 0.0, n: int = 28) -> void:
	forme(pts_ellipse(centre, rx, ry, angle, n), fond, contour, ep)

## Triangle (corne, pointe, croc) : base a-b, sommet c.
func pic(a: Vector2, b: Vector2, c: Vector2, fond: Color, contour: Color = ENCRE, ep: float = 2.0) -> void:
	forme(PackedVector2Array([a, c, b]), fond, contour, ep)

## Calotte : la part d'un disque comprise entre deux angles, fermée par la corde.
func calotte(centre: Vector2, r: float, a0: float, a1: float, fond: Color, contour: Color = SANS, ep: float = 2.0) -> void:
	forme(pts_arc(centre, r, a0, a1, 14), fond, contour, ep)

func etoile(centre: Vector2, r: float, fond: Color, rotation: float = 0.0, contour: Color = ENCRE) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(centre + Vector2.from_angle(rotation + TAU * i / 10.0) * (r if i % 2 == 0 else r * 0.45))
	forme(pts, fond, contour, 1.2)

# ------------------------------------------------------------------ traits

func anneau(centre: Vector2, r: float, couleur: Color, ep: float = 2.0) -> void:
	ci.draw_circle(centre, r, t(couleur), false, ep, true)

func arc(centre: Vector2, r: float, a0: float, a1: float, couleur: Color, ep: float = 2.0) -> void:
	ci.draw_arc(centre, r, a0, a1, maxi(6, int(absf(a1 - a0) * 8.0)), t(couleur), ep, true)

## Anneau en tirets qui tourne : `pas` = longueur d'un tiret + son vide, en unités de monde.
func pointille(centre: Vector2, r: float, couleur: Color, ep: float, pas: float, phase: float, plein: float = 0.58) -> void:
	var n := maxi(6, int(round(TAU * r / pas)))
	for i in n:
		var a := phase + TAU * i / n
		ci.draw_arc(centre, r, a, a + TAU / n * plein, 5, t(couleur), ep, true)

## Trait à bouts ronds.
func ligne(a: Vector2, b: Vector2, couleur: Color, ep: float = 2.0) -> void:
	ci.draw_line(a, b, t(couleur), ep, true)
	if alpha >= 1.0 and couleur.a >= 1.0 and ep >= 2.5:
		ci.draw_circle(a, ep * 0.5, couleur, true, -1.0, true)
		ci.draw_circle(b, ep * 0.5, couleur, true, -1.0, true)

func filet(pts: PackedVector2Array, couleur: Color, ep: float = 2.0) -> void:
	ci.draw_polyline(pts, t(couleur), ep, true)

## Trait épais cerné (manche, bâton, queue) : le contour d'abord, la matière par-dessus.
func baton(a: Vector2, b: Vector2, fond: Color, ep: float, contour: Color = ENCRE) -> void:
	ligne(a, b, contour, ep + 3.0)
	ligne(a, b, fond, ep)

func ruban(pts: PackedVector2Array, fond: Color, ep: float, contour: Color = ENCRE) -> void:
	if contour.a > 0.0:
		ci.draw_polyline(pts, t(contour), ep + 3.0, true)
	ci.draw_polyline(pts, t(fond), ep, true)

## Bande de largeur variable le long d'une épine (cape, natte) ; bords cernés.
func bande(epine: PackedVector2Array, demi: PackedFloat32Array, fond: Color, contour: Color, ep: float = 2.0) -> void:
	var gauche := PackedVector2Array()
	var droite := PackedVector2Array()
	for i in epine.size():
		var sens: Vector2 = (epine[mini(i + 1, epine.size() - 1)] - epine[maxi(i - 1, 0)]).normalized().orthogonal()
		gauche.append(epine[i] + sens * demi[i])
		droite.append(epine[i] - sens * demi[i])
	var c := PackedColorArray([t(fond), t(fond), t(fond), t(fond)])
	for i in epine.size() - 1:
		ci.draw_primitive(PackedVector2Array([gauche[i], gauche[i + 1], droite[i + 1], droite[i]]), c, PackedVector2Array())
	droite.reverse()
	gauche.append_array(droite)
	ci.draw_polyline(gauche, t(contour), ep, true)

## Croissant d'un coup : plein côté tête (a1), effilé et transparent côté queue (a0).
func taillade(centre: Vector2, rayon: float, a0: float, a1: float, epais: float, couleur: Color, force: float = 1.0) -> void:
	var n := maxi(2, int(ceil(absf(a1 - a0) / 0.12)))
	var dehors := PackedVector2Array()
	var dedans := PackedVector2Array()
	var teintes := PackedColorArray()
	for i in n + 1:
		var u := float(i) / n
		var d := Vector2.from_angle(lerpf(a0, a1, u))
		dehors.append(centre + d * rayon)
		dedans.append(centre + d * (rayon - epais * pow(u, 0.6)))
		teintes.append(t(couleur, force * (0.15 + 0.85 * u)))
	for i in n:
		ci.draw_primitive(PackedVector2Array([dehors[i], dehors[i + 1], dedans[i + 1], dedans[i]]),
			PackedColorArray([teintes[i], teintes[i + 1], teintes[i + 1], teintes[i]]), PackedVector2Array())

# ------------------------------------------------------------------ lumière, visages, texte

## Halo doux (dégradé radial). `force` multiplie l'opacité de la couleur.
func lueur(centre: Vector2, rayon: float, couleur: Color, force: float = 1.0) -> void:
	ci.draw_texture_rect(_texture_halo(), Rect2(centre - Vector2(rayon, rayon), Vector2(rayon, rayon) * 2.0), false, t(couleur, force))

## Ombre douce posée au sol : une tache sombre aux bords fondus (rectangles texturés : toutes les
## ombres d'une image partent en un seul appel de dessin).
func ombre(centre: Vector2, rx: float, ry: float, force: float = 1.0) -> void:
	ci.draw_texture_rect(_texture_ombre(), Rect2(centre - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, t(Color(0.0, 0.0, 0.0, 0.62), force))

## Deux yeux de part et d'autre de l'axe `angle`, à `dist` × r du centre.
func yeux(centre: Vector2, r: float, couleur: Color, ecart: float = 0.45, dist: float = 0.45, taille: float = 0.14, angle: float = 0.0) -> void:
	for s: float in [-ecart, ecart]:
		ci.draw_circle(centre + Vector2.from_angle(angle + s) * r * dist, maxf(1.6, r * taille), t(couleur), true, -1.0, true)

## Texte centré sur `pos` (ligne de base), cerné de noir.
func texte(pos: Vector2, chaine: String, taille: int, couleur: Color) -> void:
	var largeur := 260.0
	var o := pos - Vector2(largeur * 0.5, 0.0)
	ci.draw_string_outline(police(), o, chaine, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, 4, t(Color(0.0, 0.0, 0.0, 0.85)))
	ci.draw_string(police(), o, chaine, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, t(couleur))

static func police() -> Font:
	if _police == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
		f.font_weight = 800
		_police = f
	return _police

static func _texture_halo() -> Texture2D:
	if _halo == null:
		_halo = _radial(PackedFloat32Array([0.0, 0.4, 1.0]), PackedFloat32Array([1.0, 0.4, 0.0]), 128)
	return _halo

static func _texture_ombre() -> Texture2D:
	if _ombre == null:
		_ombre = _radial(PackedFloat32Array([0.0, 0.55, 0.8, 1.0]), PackedFloat32Array([1.0, 0.85, 0.35, 0.0]), 64)
	return _ombre

## Dégradé radial blanc dont l'opacité suit `alphas` du centre vers le bord.
static func _radial(pas: PackedFloat32Array, alphas: PackedFloat32Array, taille: int) -> Texture2D:
	var g := Gradient.new()
	var teintes := PackedColorArray()
	for a in alphas:
		teintes.append(Color(1.0, 1.0, 1.0, a))
	g.offsets = pas
	g.colors = teintes
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = taille
	tex.height = taille
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
