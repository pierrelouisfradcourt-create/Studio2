extends RefCounted
## Outils de tracé partagés par les calques du Monde : halos, arcs en pointillé, formes cernées,
## textes cernés, contours des télégraphes. Fonctions statiques qui dessinent sur le CanvasItem
## reçu (à n'appeler que depuis son `_draw`).
##   const Trace = preload("res://jeu/monde/trace.gd")   puis   Trace.halo(self, p, 40.0, c, 0.5)

## Contour sombre commun à tout ce qui a un corps dans le monde.
const CERNE := Color("#140507")
const TAILLE_HALO := 128

static var _halo: Texture2D = null
static var _police: Font = null

## Halo radial (couleur au centre, transparent au bord), de rayon `r`.
static func halo(c: CanvasItem, p: Vector2, r: float, couleur: Color, alpha: float = 1.0) -> void:
	if _halo == null:
		_halo = _fabriquer_halo()
	var teinte := Color(couleur.r, couleur.g, couleur.b, couleur.a * clampf(alpha, 0.0, 1.0))
	c.draw_texture_rect(_halo, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, teinte)

static func _fabriquer_halo() -> Texture2D:
	var degrade := Gradient.new()
	degrade.set_color(0, Color(1, 1, 1, 1))
	degrade.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = degrade
	t.width = TAILLE_HALO
	t.height = TAILLE_HALO
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

## Même couleur, autre opacité.
static func voile(couleur: Color, alpha: float) -> Color:
	return Color(couleur.r, couleur.g, couleur.b, clampf(alpha, 0.0, 1.0))

## Nombre de segments d'un arc de rayon `r` et d'ouverture `angle` : lisse sans gaspiller.
static func segments(r: float, angle: float = TAU) -> int:
	return clampi(int(ceil(absf(angle) * sqrt(maxf(r, 1.0)) * 1.6)), 6, 96)

## Points d'un arc de cercle, de a0 à a1.
static func arc(centre: Vector2, r: float, a0: float, a1: float, n: int = 0) -> PackedVector2Array:
	if n <= 0:
		n = segments(r, a1 - a0)
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(centre + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n))) * r)
	return pts

## Secteur (part de tarte) : la pointe puis l'arc.
static func secteur(centre: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array([centre])
	pts.append_array(arc(centre, r, a0, a1))
	return pts

## Ellipse pleine ou cernée, d'axes rx et ry.
static func ellipse(centre: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := segments(maxf(rx, ry))
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## Rectangle orienté partant de `origine` dans la direction `angle` (télégraphe en ligne).
static func bande(origine: Vector2, angle: float, longueur: float, largeur: float) -> PackedVector2Array:
	var u := Vector2.from_angle(angle)
	var v := u.orthogonal() * (largeur / 2.0)
	return PackedVector2Array([origine + v, origine + u * longueur + v, origine + u * longueur - v, origine - v])

## Polygone plein avec son contour anticrénelé (le contour adoucit aussi le bord du plein).
static func forme(c: CanvasItem, pts: PackedVector2Array, fond: Color, cerne: Color = CERNE, largeur: float = 2.0) -> void:
	if pts.size() < 3:
		return
	if fond.a > 0.0:
		c.draw_colored_polygon(pts, fond)
	if largeur > 0.0 and cerne.a > 0.0:
		contour(c, pts, cerne, largeur)

## Contour fermé anticrénelé.
static func contour(c: CanvasItem, pts: PackedVector2Array, couleur: Color, largeur: float) -> void:
	var boucle := PackedVector2Array(pts)
	boucle.append(pts[0])
	c.draw_polyline(boucle, couleur, largeur, true)

## Disque plein cerné.
static func disque(c: CanvasItem, p: Vector2, r: float, fond: Color, cerne: Color = CERNE, largeur: float = 2.0) -> void:
	c.draw_circle(p, r, fond, true, -1.0, true)
	if largeur > 0.0:
		c.draw_circle(p, r, cerne, false, largeur, true)

## Cercle en pointillé qui tourne (`decalage` en unités le long du cercle).
static func cercle_pointille(c: CanvasItem, centre: Vector2, r: float, couleur: Color, largeur: float, plein: float, vide: float, decalage: float = 0.0) -> void:
	if r <= 1.0:
		return
	var n := maxi(4, int(round(TAU * r / (plein + vide))))
	var pas := TAU / float(n)
	var part := pas * plein / (plein + vide)
	var a0 := fposmod(decalage / r, pas)
	for i in n:
		var a := a0 + pas * float(i)
		c.draw_arc(centre, r, a, a + part, 5, couleur, largeur, true)

## Ligne droite en pointillé qui défile.
static func ligne_pointillee(c: CanvasItem, a: Vector2, b: Vector2, couleur: Color, largeur: float, plein: float, vide: float, decalage: float = 0.0) -> void:
	var longueur := a.distance_to(b)
	if longueur < 1.0:
		return
	var u := (b - a) / longueur
	var d := fposmod(decalage, plein + vide) - (plein + vide)
	while d < longueur:
		var d0 := maxf(0.0, d)
		var d1 := minf(longueur, d + plein)
		if d1 > d0:
			c.draw_line(a + u * d0, a + u * d1, couleur, largeur, true)
		d += plein + vide

## Dégradé vertical dans un rectangle (haut → bas).
static func degrade_vertical(c: CanvasItem, r: Rect2, haut: Color, bas: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([haut, haut, bas, bas]))

## Dégradé horizontal dans un rectangle (gauche → droite).
static func degrade_horizontal(c: CanvasItem, r: Rect2, gauche: Color, droite: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_polygon(pts, PackedColorArray([gauche, droite, droite, gauche]))

## Police des libellés du monde : celle du système, grasse, nette à tout zoom de caméra.
static func police() -> Font:
	if _police == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
		f.font_weight = 700
		f.multichannel_signed_distance_field = true
		_police = f
	return _police

## Libellé centré sur `centre`, cerné de sombre : lisible sur n'importe quel sol.
static func texte(c: CanvasItem, centre: Vector2, libelle: String, taille: int, couleur: Color) -> void:
	if libelle == "":
		return
	var f := police()
	var largeur := f.get_string_size(libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille).x
	var base := centre + Vector2(-largeur / 2.0, float(taille) * 0.36)
	c.draw_string_outline(f, base, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 5, Color(0, 0, 0, 0.85))
	c.draw_string(f, base, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, couleur)
