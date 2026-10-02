extends RefCounted
## Pinceau des créatures : les formes de base, nettes (anticrénelées) et cernées d'un même trait
## sombre. Il dessine sur le CanvasItem qu'on lui donne, PENDANT le `_draw` de celui-ci, entre
## `commencer(ci)` et `finir()`.
## `alpha` s'applique à tout ce qui est dessiné ensuite (apparition, clignotement, filigrane).
##
## COÛT : aucune forme ne part seule. Elles s'accumulent dans un lot de triangles
## (jeu/theme/triangles.gd, mêmes triangles que les gestes du moteur, donc même image) que
## `finir()` trace en UN appel de dessin. Les lueurs et les ombres en font partie : leurs deux
## dégradés vivent dans une même texture (l'atlas), que le lot emporte. Seul un texte coupe le
## lot : ce qui précède part, le texte est posé, le lot reprend. Un corps d'ennemi coûte ainsi
## 1 appel de dessin au lieu de 35 à 60.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const ENCRE: Color = Couleurs.PAL.enemyOutline
const SANS := Color(0.0, 0.0, 0.0, 0.0) # « pas de contour »
const TRAIT := 2.5
const NEUTRE := Transform2D.IDENTITY
const FORMES := 512 # tracés gardés en mémoire (ellipses, arcs, calottes autour de l'origine)

const HALO := 128 # px : côté du dégradé des lueurs
const OMBRE := 64 # px : côté du dégradé des ombres
const ATLAS := Vector2i(HALO + OMBRE + 20, HALO + 2)

static var _atlas: Texture2D = null
static var _zone_halo := Rect2()
static var _zone_ombre := Rect2()
static var _blanc := Vector2.ZERO
static var _police: Font = null
static var _formes := {} # [genre, mesures…] -> PackedVector2Array autour de l'origine

var ci: CanvasItem
var alpha := 1.0
var lot := Triangles.new()

func _init(p_ci: CanvasItem) -> void:
	ci = p_ci

func t(couleur: Color, force: float = 1.0) -> Color:
	return Color(couleur.r, couleur.g, couleur.b, couleur.a * alpha * force)

## Début d'un dessin sur `p_ci` (au début de son `_draw`).
func commencer(p_ci: CanvasItem) -> void:
	ci = p_ci
	alpha = 1.0
	lot.repere = NEUTRE
	lot.texture = _atlas_pret()
	lot.blanc = _blanc

## Fin du dessin : tout ce qui attend dans le lot est tracé.
func finir() -> void:
	lot.tracer(ci)
	alpha = 1.0
	lot.repere = NEUTRE

## Repère de dessin (position, rotation, écrasement) pour tout ce qui suit.
func poser(m: Transform2D) -> void:
	lot.repere = m

func lever() -> void:
	lot.repere = NEUTRE

## Avant de poser un texte : le lot part, le repère est donné au moteur.
func _direct() -> void:
	lot.tracer(ci)
	if lot.repere != NEUTRE:
		ci.draw_set_transform_matrix(lot.repere)

func _fin_direct() -> void:
	if lot.repere != NEUTRE:
		ci.draw_set_transform_matrix(NEUTRE)

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

## Les points d'un arc au trait, comme draw_arc les place (n points de a0 à a1), autour de l'origine.
static func pts_trait_arc(r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ouverture := clampf(a1 - a0, -TAU, TAU)
	for i in n:
		pts.append(Vector2.from_angle(i / (n - 1.0) * ouverture + a0) * r)
	return pts

## Un tracé autour de l'origine, gardé en mémoire : il n'est calculé qu'une fois par jeu de mesures.
static func _forme_gardee(cle: Array) -> PackedVector2Array:
	var pts = _formes.get(cle)
	if pts == null:
		if _formes.size() >= FORMES:
			_formes.clear()
		match cle[0]:
			"ellipse": pts = pts_ellipse(Vector2.ZERO, cle[1], cle[2], cle[3], cle[4])
			"calotte": pts = pts_arc(Vector2.ZERO, cle[1], cle[2], cle[3], 14)
			_: pts = pts_trait_arc(cle[1], cle[2], cle[3], cle[4])
		_formes[cle] = pts
	return pts

# ------------------------------------------------------------------ formes pleines

func disque(centre: Vector2, r: float, fond: Color, contour: Color = ENCRE, ep: float = TRAIT) -> void:
	lot.disque(centre, r, t(fond))
	if contour.a > 0.0:
		lot.cercle(centre, r, t(contour), ep)

## Polygone plein, bord lissé par son contour (ou par un filet de sa propre couleur). `place` :
## où poser des points donnés autour de l'origine.
func forme(pts: PackedVector2Array, fond: Color, contour: Color = ENCRE, ep: float = TRAIT, place: Transform2D = NEUTRE) -> void:
	lot.polygone(pts, t(fond), place)
	if contour.a > 0.0:
		lot.contour(pts, t(contour), ep, alpha >= 1.0 and contour.a >= 1.0, place)
	elif alpha >= 1.0 and fond.a >= 1.0:
		lot.contour(pts, fond, 1.0, false, place)

func ellipse(centre: Vector2, rx: float, ry: float, fond: Color, contour: Color = ENCRE, ep: float = TRAIT, angle: float = 0.0, n: int = 28) -> void:
	forme(_forme_gardee(["ellipse", rx, ry, angle, n]), fond, contour, ep, Transform2D(0.0, centre))

## Triangle (corne, pointe, croc) : base a-b, sommet c.
func pic(a: Vector2, b: Vector2, c: Vector2, fond: Color, contour: Color = ENCRE, ep: float = 2.0) -> void:
	forme(PackedVector2Array([a, c, b]), fond, contour, ep)

## Calotte : la part d'un disque comprise entre deux angles, fermée par la corde.
func calotte(centre: Vector2, r: float, a0: float, a1: float, fond: Color, contour: Color = SANS, ep: float = 2.0) -> void:
	forme(_forme_gardee(["calotte", r, a0, a1]), fond, contour, ep, Transform2D(0.0, centre))

func etoile(centre: Vector2, r: float, fond: Color, rotation: float = 0.0, contour: Color = ENCRE) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(centre + Vector2.from_angle(rotation + TAU * i / 10.0) * (r if i % 2 == 0 else r * 0.45))
	forme(pts, fond, contour, 1.2)

## Rectangle plein, sans lissage ; couleur telle quelle (`alpha` ne s'y applique pas).
func rect(r: Rect2, couleur: Color) -> void:
	lot.rect(r, couleur)

## Triangle ou quadrilatère, une couleur par sommet ; couleurs telles quelles.
func primitive(pts: PackedVector2Array, couleurs: PackedColorArray) -> void:
	lot.primitive(pts, couleurs)

# ------------------------------------------------------------------ traits

func anneau(centre: Vector2, r: float, couleur: Color, ep: float = 2.0) -> void:
	lot.cercle(centre, r, t(couleur), ep)

func arc(centre: Vector2, r: float, a0: float, a1: float, couleur: Color, ep: float = 2.0) -> void:
	lot.arc(centre, r, a0, a1, maxi(6, int(absf(a1 - a0) * 8.0)), t(couleur), ep)

## Anneau en tirets qui tourne : `pas` = longueur d'un tiret + son vide, en unités de monde.
## Un seul tiret est calculé ; les autres sont le même, tourné.
func pointille(centre: Vector2, r: float, couleur: Color, ep: float, pas: float, phase: float, plein: float = 0.58) -> void:
	var n := maxi(6, int(round(TAU * r / pas)))
	var tiret := _forme_gardee(["arc", r, 0.0, TAU / n * plein, 5])
	var teinte := t(couleur)
	for i in n:
		lot.polyligne(tiret, teinte, ep, true, Transform2D(phase + TAU * i / n, centre))

## Trait à bouts ronds.
func ligne(a: Vector2, b: Vector2, couleur: Color, ep: float = 2.0) -> void:
	lot.ligne(a, b, t(couleur), ep)
	if alpha >= 1.0 and couleur.a >= 1.0 and ep >= 2.5:
		lot.disque(a, ep * 0.5, couleur)
		lot.disque(b, ep * 0.5, couleur)

## Trait droit sans bouts ronds, lissé ou non ; couleur telle quelle.
func segment(a: Vector2, b: Vector2, couleur: Color, ep: float, lisse: bool = false) -> void:
	lot.ligne(a, b, couleur, ep, lisse)

func filet(pts: PackedVector2Array, couleur: Color, ep: float = 2.0) -> void:
	lot.polyligne(pts, t(couleur), ep)

## Trait épais cerné (manche, bâton, queue) : le contour d'abord, la matière par-dessus.
func baton(a: Vector2, b: Vector2, fond: Color, ep: float, contour: Color = ENCRE) -> void:
	ligne(a, b, contour, ep + 3.0)
	ligne(a, b, fond, ep)

func ruban(pts: PackedVector2Array, fond: Color, ep: float, contour: Color = ENCRE) -> void:
	if contour.a > 0.0:
		lot.polyligne(pts, t(contour), ep + 3.0)
	lot.polyligne(pts, t(fond), ep)

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
		lot.primitive(PackedVector2Array([gauche[i], gauche[i + 1], droite[i + 1], droite[i]]), c)
	droite.reverse()
	gauche.append_array(droite)
	lot.polyligne(gauche, t(contour), ep)

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
		lot.primitive(PackedVector2Array([dehors[i], dehors[i + 1], dedans[i + 1], dedans[i]]),
			PackedColorArray([teintes[i], teintes[i + 1], teintes[i + 1], teintes[i]]))

# ------------------------------------------------------------------ lumière, visages, texte

## Halo doux (dégradé radial). `force` multiplie l'opacité de la couleur.
func lueur(centre: Vector2, rayon: float, couleur: Color, force: float = 1.0) -> void:
	lot.vignette(Rect2(centre - Vector2(rayon, rayon), Vector2(rayon, rayon) * 2.0), t(couleur, force), _zone_halo)

## Ombre douce posée au sol : une tache sombre aux bords fondus.
func ombre(centre: Vector2, rx: float, ry: float, force: float = 1.0) -> void:
	lot.vignette(Rect2(centre - Vector2(rx, ry), Vector2(rx, ry) * 2.0), t(Color(0.0, 0.0, 0.0, 0.62), force), _zone_ombre)

## Deux yeux de part et d'autre de l'axe `angle`, à `dist` × r du centre.
func yeux(centre: Vector2, r: float, couleur: Color, ecart: float = 0.45, dist: float = 0.45, taille: float = 0.14, angle: float = 0.0) -> void:
	for s: float in [-ecart, ecart]:
		lot.disque(centre + Vector2.from_angle(angle + s) * r * dist, maxf(1.6, r * taille), t(couleur))

## Texte centré sur `pos` (ligne de base), cerné de noir.
func texte(pos: Vector2, chaine: String, taille: int, couleur: Color) -> void:
	var largeur := 260.0
	var o := pos - Vector2(largeur * 0.5, 0.0)
	_direct()
	ci.draw_string_outline(police(), o, chaine, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, 4, t(Color(0.0, 0.0, 0.0, 0.85)))
	ci.draw_string(police(), o, chaine, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, t(couleur))
	_fin_direct()

static func police() -> Font:
	if _police == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
		f.font_weight = 800
		_police = f
	return _police

## L'atlas : le dégradé des lueurs, celui des ombres et un carré blanc dans UNE texture, pour que
## tout un dessin parte en un appel. Chaque dégradé est bordé d'un pixel répété : étiré, il rend
## au bord ce que rendrait sa texture seule.
static func _atlas_pret() -> Texture2D:
	if _atlas == null:
		var image := Image.create(ATLAS.x, ATLAS.y, false, Image.FORMAT_RGBA8)
		_zone_halo = _coller(image, _radial(PackedFloat32Array([0.0, 0.4, 1.0]), PackedFloat32Array([1.0, 0.4, 0.0]), HALO), Vector2i(1, 1))
		_zone_ombre = _coller(image, _radial(PackedFloat32Array([0.0, 0.55, 0.8, 1.0]), PackedFloat32Array([1.0, 0.85, 0.35, 0.0]), OMBRE), Vector2i(HALO + 4, 1))
		var carre := Rect2i(HALO + OMBRE + 8, 1, 8, 8)
		image.fill_rect(carre, Color.WHITE)
		_blanc = Vector2(carre.get_center()) / Vector2(ATLAS)
		_atlas = ImageTexture.create_from_image(image)
	return _atlas

## Colle `motif` dans l'atlas à `coin`, borde d'un pixel répété, et rend sa zone (en parts de l'atlas).
static func _coller(image: Image, motif: Image, coin: Vector2i) -> Rect2:
	var t := motif.get_size()
	for y in range(-1, t.y + 1):
		for x in range(-1, t.x + 1):
			image.set_pixel(coin.x + x, coin.y + y, motif.get_pixel(clampi(x, 0, t.x - 1), clampi(y, 0, t.y - 1)))
	return Rect2(Vector2(coin) / Vector2(ATLAS), Vector2(t) / Vector2(ATLAS))

## Dégradé radial blanc dont l'opacité suit `alphas` du centre vers le bord : l'image que fabrique
## le moteur (GradientTexture2D) ; sans rendu (essai headless), la même formule calculée ici.
static func _radial(pas: PackedFloat32Array, alphas: PackedFloat32Array, taille: int) -> Image:
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
	var image := tex.get_image()
	if image == null or image.is_empty():
		image = Image.create(taille, taille, false, Image.FORMAT_RGBA8)
		for y in taille:
			for x in taille:
				image.set_pixel(x, y, g.sample(minf(1.0, (Vector2(x, y) / (taille - 1.0)).distance_to(Vector2(0.5, 0.5)) * 2.0)))
	image.convert(Image.FORMAT_RGBA8)
	return image
