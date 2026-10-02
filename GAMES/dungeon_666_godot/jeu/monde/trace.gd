extends RefCounted
## Outils de tracé partagés par les calques du Monde : halos, jauges, pointillés, formes cernées,
## traînées, textes cernés. Fonctions statiques qui dessinent sur le CanvasItem reçu (à n'appeler
## que depuis son `_draw`).
##   const Trace = preload("res://jeu/monde/trace.gd")   puis   Trace.halo(self, p, 40.0, c, 0.5)
##
## Coût : en rendu Compatibility, un rectangle (texturé ou non), une ligne non lissée et une
## primitive de 3 ou 4 points partent par LOTS ; un polygone, un arc ou un trait lissé coûte un
## appel de dessin chacun. Les outils d'ici préfèrent donc les textures fabriquées en mémoire
## (halo, jauge) et les primitives.

## Contour sombre commun à tout ce qui a un corps dans le monde.
const CERNE := Color("#140507")
const TAILLE_HALO := 128
const TAILLE_JAUGE := 256

const TAILLE_PLEIN := 256

static var _halo: Texture2D = null
static var _jauge: Texture2D = null
static var _plein: Texture2D = null
static var _pastilles := {}
static var _police: Font = null

## Un lot de traits de même largeur, tracés en UN appel de dessin (draw_multiline_colors) :
## contours de zones, fronts de jauges, arcs. Chaque segment garde sa couleur.
##   var lot := Trace.Lot.new()   lot.cercle(p, r, c)   lot.tracer(self, 2.5)
class Lot:
	var pts := PackedVector2Array()
	var couleurs := PackedColorArray()

	func segment(a: Vector2, b: Vector2, couleur: Color) -> void:
		pts.append(a)
		pts.append(b)
		couleurs.append(couleur)

	func polyligne(ligne: PackedVector2Array, couleur: Color, fermee: bool = false) -> void:
		for i in ligne.size() - 1:
			segment(ligne[i], ligne[i + 1], couleur)
		if fermee and ligne.size() > 2:
			segment(ligne[ligne.size() - 1], ligne[0], couleur)

	func arc(centre: Vector2, r: float, a0: float, a1: float, couleur: Color) -> void:
		var n := clampi(int(ceil(absf(a1 - a0) * sqrt(maxf(r, 1.0)) * 1.6)), 4, 96)
		var avant := centre + Vector2.from_angle(a0) * r
		for i in range(1, n + 1):
			var ici := centre + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n))) * r
			segment(avant, ici, couleur)
			avant = ici

	func cercle(centre: Vector2, r: float, couleur: Color) -> void:
		arc(centre, r, 0.0, TAU, couleur)

	## Cercle en pointillé (`decalage` en unités le long du cercle : il tourne).
	func pointille(centre: Vector2, r: float, couleur: Color, plein: float, vide: float, decalage: float = 0.0) -> void:
		if r <= 1.0:
			return
		var n := maxi(4, int(round(TAU * r / (plein + vide))))
		var pas := TAU / float(n)
		var part := pas * plein / (plein + vide)
		var a0 := fposmod(decalage / r, pas)
		var brins := maxi(1, int(ceil(part * r / 7.0)))
		for i in n:
			var a := a0 + pas * float(i)
			for k in brins:
				var debut := centre + Vector2.from_angle(a + part * float(k) / float(brins)) * r
				segment(debut, centre + Vector2.from_angle(a + part * float(k + 1) / float(brins)) * r, couleur)

	func tracer(c: CanvasItem, largeur: float) -> void:
		if pts.size() >= 2:
			c.draw_multiline_colors(pts, couleurs, largeur, true)

## Halo radial doux (couleur au centre, transparent au bord), de rayon `r`.
static func halo(c: CanvasItem, p: Vector2, r: float, couleur: Color, alpha: float = 1.0) -> void:
	halo_ovale(c, p, r, r, couleur, alpha)

## Halo en ellipse (flaque de lumière au sol).
static func halo_ovale(c: CanvasItem, p: Vector2, rx: float, ry: float, couleur: Color, alpha: float = 1.0) -> void:
	if _halo == null:
		_halo = _radial(TAILLE_HALO, [0.0, 0.2, 0.45, 0.72, 1.0], [1.0, 0.62, 0.3, 0.09, 0.0])
	var teinte := Color(couleur.r, couleur.g, couleur.b, couleur.a * clampf(alpha, 0.0, 1.0))
	c.draw_texture_rect(_halo, Rect2(p - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, teinte)

## Disque « jauge » : presque vide au centre, de plus en plus dense vers son bord. C'est le
## front d'une frappe qui avance de l'intérieur vers le bord de la zone.
static func texture_jauge() -> Texture2D:
	if _jauge == null:
		_jauge = _radial(TAILLE_JAUGE, [0.0, 0.4, 0.8, 0.965, 0.988, 1.0], [0.0, 0.05, 0.4, 1.0, 1.0, 0.0])
	return _jauge

static func jauge(c: CanvasItem, p: Vector2, r: float, couleur: Color, alpha: float = 1.0) -> void:
	var teinte := Color(couleur.r, couleur.g, couleur.b, couleur.a * clampf(alpha, 0.0, 1.0))
	c.draw_texture_rect(texture_jauge(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, teinte)

## Disque plein au bord net (remplissage d'une zone ronde) : un rectangle texturé, qui part en lot.
static func plein(c: CanvasItem, p: Vector2, r: float, couleur: Color) -> void:
	if _plein == null:
		_plein = _radial(TAILLE_PLEIN, [0.0, 0.984, 1.0], [1.0, 1.0, 0.0])
	c.draw_texture_rect(_plein, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, couleur)

## Pastille cernée à cœur clair (orbe, perle) : une texture par jeu de couleurs, gardée en mémoire.
static func pastille(c: CanvasItem, p: Vector2, r: float, coeur: Color, corps: Color, cerne: Color) -> void:
	var cle := "%s%s%s" % [coeur.to_html(), corps.to_html(), cerne.to_html()]
	if not _pastilles.has(cle):
		var degrade := Gradient.new()
		degrade.offsets = PackedFloat32Array([0.0, 0.34, 0.42, 0.7, 0.76, 0.95, 1.0])
		degrade.colors = PackedColorArray([coeur, coeur, corps, corps, cerne, cerne, voile(cerne, 0.0)])
		_pastilles[cle] = _texture_radiale(degrade, 96)
	c.draw_texture_rect(_pastilles[cle], Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false)

## Texture radiale blanche dont l'opacité suit `alphas` du centre (0) au bord (1).
static func _radial(taille: int, reperes: Array, alphas: Array) -> Texture2D:
	var degrade := Gradient.new()
	var couleurs := PackedColorArray()
	for a in alphas:
		couleurs.append(Color(1, 1, 1, a))
	degrade.offsets = PackedFloat32Array(reperes)
	degrade.colors = couleurs
	return _texture_radiale(degrade, taille)

static func _texture_radiale(degrade: Gradient, taille: int) -> Texture2D:
	var t := GradientTexture2D.new()
	t.gradient = degrade
	t.width = taille
	t.height = taille
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

## Cadre d'un rectangle en quatre traits d'équerre non lissés (ils partent en lot) : murs, piliers.
static func cadre(c: CanvasItem, r: Rect2, couleur: Color, largeur: float) -> void:
	var demi := Vector2(largeur / 2.0, 0.0)
	var bas := Vector2(0.0, r.size.y)
	c.draw_line(r.position - demi, r.position + Vector2(r.size.x, 0.0) + demi, couleur, largeur)
	c.draw_line(r.position + bas - demi, r.end + demi, couleur, largeur)
	c.draw_line(r.position, r.position + bas, couleur, largeur)
	c.draw_line(r.end - bas, r.end, couleur, largeur)

## Triangle à trois couleurs (primitive : part en lot avec ses voisines).
static func triangle(c: CanvasItem, a: Vector2, b: Vector2, d: Vector2, ca: Color, cb: Color, cd: Color) -> void:
	c.draw_primitive(PackedVector2Array([a, b, d]), PackedColorArray([ca, cb, cd]), PackedVector2Array())

## Traînée effilée derrière un projectile : large et colorée à la tête, transparente à la queue.
static func trainee(c: CanvasItem, tete: Vector2, queue: Vector2, largeur: float, couleur: Color, alpha: float = 1.0) -> void:
	var travers := (tete - queue).orthogonal().normalized() * (largeur / 2.0)
	var plein := voile(couleur, couleur.a * alpha)
	triangle(c, tete + travers, tete - travers, queue, plein, plein, voile(couleur, 0.0))

## Cercle en pointillé qui tourne (`decalage` en unités le long du cercle) : un seul appel de dessin.
static func cercle_pointille(c: CanvasItem, centre: Vector2, r: float, couleur: Color, largeur: float, plein: float, vide: float, decalage: float = 0.0) -> void:
	var lot := Lot.new()
	lot.pointille(centre, r, couleur, plein, vide, decalage)
	lot.tracer(c, largeur)

## Ligne droite en pointillé qui défile : un seul appel de dessin.
static func ligne_pointillee(c: CanvasItem, a: Vector2, b: Vector2, couleur: Color, largeur: float, plein: float, vide: float, decalage: float = 0.0) -> void:
	var longueur := a.distance_to(b)
	if longueur < 1.0:
		return
	var u := (b - a) / longueur
	var d := fposmod(decalage, plein + vide) - (plein + vide)
	var pts := PackedVector2Array()
	while d < longueur:
		var d0 := maxf(0.0, d)
		var d1 := minf(longueur, d + plein)
		if d1 > d0:
			pts.append(a + u * d0)
			pts.append(a + u * d1)
		d += plein + vide
	if pts.size() >= 2:
		c.draw_multiline(pts, couleur, largeur, true)

## Dégradé vertical dans un rectangle (haut → bas).
static func degrade_vertical(c: CanvasItem, r: Rect2, haut: Color, bas: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_primitive(pts, PackedColorArray([haut, haut, bas, bas]), PackedVector2Array())

## Dégradé horizontal dans un rectangle (gauche → droite).
static func degrade_horizontal(c: CanvasItem, r: Rect2, gauche: Color, droite: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	c.draw_primitive(pts, PackedColorArray([gauche, droite, droite, gauche]), PackedVector2Array())

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
	c.draw_string_outline(f, base, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, 6, Color(0, 0, 0, 0.9))
	c.draw_string(f, base, libelle, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, couleur)
