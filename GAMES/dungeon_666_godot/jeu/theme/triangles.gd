extends RefCounted
## Un LOT DE TRIANGLES : les formes d'un dessin (disques, polygones, traits lissés) sont ajoutées
## une à une, puis tracées en UN SEUL appel de dessin (`tracer`). C'est ce qui rend un corps bon
## marché : en rendu Compatibility, chaque polygone, chaque disque lissé (2 appels) et chaque trait
## lissé (3 appels) du moteur coûte ses propres appels ; ici tout part ensemble.
## Brique commune au Monde (créatures, ramassables) et au HUD (commandes, fil des étages).
##   const Triangles = preload("res://jeu/theme/triangles.gd")
##   var lot := Triangles.new()   lot.disque(p, 12.0, c)   lot.cercle(p, 12.0, cerne, 2.5)   lot.tracer(self)
## Un lot peut porter UNE texture (`texture`, `vignette`) : halos et ombres partent avec les formes.
##
## MÊME IMAGE que les gestes du moteur : chaque forme reprend les triangles que Godot fabrique
## pour `draw_circle`, `draw_colored_polygon`, `draw_polyline` et `draw_line` (mêmes points, même
## frange de lissage de 1,25 u, même ordre). Portage de servers/rendering/renderer_canvas_cull.cpp
## (4.6) : canvas_item_add_ellipse, _polyline, _line.
##
## Coût du calcul : une forme est un GABARIT [points, trame, nombre de points pleins, clé] — ses points
## autour de l'origine (les pleins d'abord, la frange transparente ensuite) et sa TRAME (les
## triangles, par numéros de points). Un gabarit est gardé en mémoire : une forme déjà vue (même
## rayon, mêmes points) ne coûte que trois recopies, où qu'elle soit posée (`place`). Les trames
## sont partagées par toutes les formes de même structure.

const PLUME := 1.25 # u : frange de lissage (FEATHER_SIZE du moteur)
const SEGMENTS := 64 # côtés d'un cercle (ellipse_segments du moteur)
const MEMOIRE := 768 # gabarits gardés par génération
const DECALAGES := 3000 # trames décalées gardées, toutes formes confondues
const TEINTES := 256 # couleurs dont les blocs sont gardés
const NEUTRE := Transform2D.IDENTITY
const TRAME_DISQUE := -1
const TRAME_DISQUE_NET := -2
const TRAME_LIGNE := -3
const TRAME_QUAD := -4
const TRAME_TRIANGLE := -5

static var _unite := PackedVector2Array()
static var _trames := {} # clé -> [numéros, {base -> numéros décalés}]
static var _decalages := 0
static var _blocs := {} # couleur -> {tailles -> PackedColorArray}
static var _neufs := {} # clé d'une forme -> son gabarit (génération en cours)
static var _vieux := {} # … génération d'avant : ce qui resservira repasse dans la neuve

## Repère appliqué aux formes ajoutées ensuite (les points sont transformés ici, pas par le moteur).
var repere := NEUTRE
## Texture commune du lot, pour ses vignettes (`vignette`), et un point BLANC de cette texture :
## c'est lui que portent les formes unies dès qu'une vignette est entrée dans le lot.
var texture: Texture2D = null
var blanc := Vector2.ZERO:
	set(v):
		if v != blanc:
			blanc = v
			_blancs.clear()

var _pts := PackedVector2Array()
var _teintes := PackedColorArray()
var _numeros := PackedInt32Array()
var _uvs := PackedVector2Array()
var _texture := false # une vignette est dans le lot : chaque point porte sa place dans la texture
var _blancs := {} # nombre de points -> autant de fois `blanc`

# ------------------------------------------------------------------ formes

## Disque plein (draw_circle plein).
func disque(centre: Vector2, r: float, couleur: Color, lisse: bool = true) -> void:
	var cle := [0, r, lisse]
	var g = _retrouver(cle)
	if g == null:
		g = _gabarit_disque(r, lisse)
		_garder(cle, g)
	_poser(g, couleur, Transform2D(0.0, centre))

## Cercle au trait (draw_circle non plein).
func cercle(centre: Vector2, r: float, couleur: Color, ep: float, lisse: bool = true) -> void:
	if ep >= 2.0 * r:
		disque(centre, r + 0.5 * ep, couleur, lisse)
		return
	var cle := [1, r, ep, lisse]
	var g = _retrouver(cle)
	if g == null:
		var pts: PackedVector2Array = Transform2D(0.0, Vector2(r, r), 0.0, Vector2.ZERO) * _cercle_unite()
		pts[SEGMENTS] = pts[0]
		g = _gabarit_polyligne(pts, ep, lisse)
		_garder(cle, g)
	_poser(g, couleur, Transform2D(0.0, centre))

## Arc de cercle au trait, de `n` points (draw_arc). Un tour complet est un trait FERMÉ si ses
## deux bouts se rejoignent là où il est posé (c'est ce que juge le moteur, au centre donné).
func arc(centre: Vector2, r: float, a0: float, a1: float, n: int, couleur: Color, ep: float, lisse: bool = true) -> void:
	var ouverture := clampf(a1 - a0, -TAU, TAU)
	var boucle := (centre + Vector2.from_angle(a0) * r).is_equal_approx(centre + Vector2.from_angle(ouverture + a0) * r)
	var cle := [5, r, a0, a1, n, ep, lisse, boucle]
	var g = _retrouver(cle)
	if g == null:
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2.from_angle(i / (n - 1.0) * ouverture + a0) * r)
		g = _gabarit_trait(pts, ep, lisse, boucle)
		_garder(cle, g)
	_poser(g, couleur, Transform2D(0.0, centre))

## Polygone plein, sans lissage (draw_colored_polygon).
func polygone(pts: PackedVector2Array, couleur: Color, place: Transform2D = NEUTRE) -> void:
	var cle := [2, pts]
	var g = _retrouver(cle)
	if g == null:
		g = [pts.duplicate(), _trame_polygone(pts), pts.size()]
		_garder([2, g[0]], g)
	if not g[1][0].is_empty():
		_poser(g, couleur, place)

## Ligne brisée (draw_polyline).
func polyligne(pts: PackedVector2Array, couleur: Color, ep: float, lisse: bool = true, place: Transform2D = NEUTRE) -> void:
	var cle := [3, ep, lisse, pts]
	var g = _retrouver(cle)
	if g == null:
		g = _gabarit_polyligne(pts, ep, lisse)
		_garder([3, ep, lisse, pts.duplicate()], g)
	_poser(g, couleur, place)

## Contour fermé et lissé d'un polygone. `recouvre` : le trait repasse sur son premier côté, ce
## qui ferme proprement l'angle de départ (à réserver aux traits opaques).
func contour(pts: PackedVector2Array, couleur: Color, ep: float, recouvre: bool = false, place: Transform2D = NEUTRE) -> void:
	var cle := [4, ep, recouvre, pts]
	var g = _retrouver(cle)
	if g == null:
		var bord := pts.duplicate()
		bord.append(pts[0])
		if recouvre:
			bord.append(pts[1])
		g = _gabarit_polyligne(bord, ep, true)
		_garder([4, ep, recouvre, pts.duplicate()], g)
	_poser(g, couleur, place)

## Segment épais (draw_line) : son rectangle, et sa frange sur les quatre côtés s'il est lissé.
func ligne(a: Vector2, b: Vector2, couleur: Color, ep: float, lisse: bool = true) -> void:
	var travers := (a - b).orthogonal().normalized()
	var t := travers * ep * 0.5
	var pts := PackedVector2Array([a + t, a - t, b - t, b + t])
	if not lisse:
		_poser([pts, _trame(TRAME_QUAD), 4], couleur, NEUTRE)
		return
	var f := travers * (PLUME * (ep if ep < 1.0 else 1.0))
	var f2 := (a - b).normalized() * f.length()
	pts.append_array(PackedVector2Array([
		a + t + f, b + t + f, a - t - f, b - t - f, a + t + f2, a - t + f2, b + t - f2, b - t - f2,
		a + t + f + f2, a - t - f + f2, b + t + f - f2, b - t - f - f2]))
	_poser([pts, _trame(TRAME_LIGNE), 4], couleur, NEUTRE)

## Triangle ou quadrilatère, une couleur par sommet (draw_primitive).
func primitive(pts: PackedVector2Array, couleurs: PackedColorArray) -> void:
	var base := _pts.size()
	_pts.append_array(pts if repere == NEUTRE else repere * pts)
	_teintes.append_array(couleurs)
	_numeros.append_array(PackedInt32Array([base, base + 1, base + 2]))
	if pts.size() == 4:
		_numeros.append_array(PackedInt32Array([base, base + 2, base + 3]))
	if _texture:
		_uvs.append_array(_blanc(pts.size()))

## Rectangle plein (draw_rect).
func rect(r: Rect2, couleur: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_poser([pts, _trame(TRAME_QUAD), 4], couleur, NEUTRE)

## Morceau de `texture` (la `zone`, en parts de sa taille) étiré dans le rectangle `r` et teinté :
## un halo, une ombre. Il part avec le reste du lot, à sa place dans l'ordre du dessin.
func vignette(r: Rect2, couleur: Color, zone: Rect2) -> void:
	if not _texture:
		_uvs = _blanc(_pts.size()).duplicate()
	_uvs.append_array(PackedVector2Array([zone.position, Vector2(zone.end.x, zone.position.y), zone.end, Vector2(zone.position.x, zone.end.y)]))
	_texture = false
	rect(r, couleur)
	_texture = true

func vide() -> bool:
	return _pts.is_empty()

## Trace tout ce qui a été ajouté, en un appel de dessin, sur `ci` (pendant son `_draw`), et vide le lot.
func tracer(ci: CanvasItem) -> void:
	if _pts.is_empty():
		return
	if _texture:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _numeros, _pts, _teintes, _uvs, PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
	else:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _numeros, _pts, _teintes)
	_pts = PackedVector2Array()
	_teintes = PackedColorArray()
	_numeros = PackedInt32Array()
	_uvs = PackedVector2Array()
	_texture = false

# ------------------------------------------------------------------ pose d'un gabarit

func _poser(g: Array, couleur: Color, place: Transform2D) -> void:
	var base := _pts.size()
	var pts: PackedVector2Array = g[0]
	var m := place if repere == NEUTRE else repere * place
	_pts.append_array(pts if m == NEUTRE else m * pts)
	_teintes.append_array(_bloc(couleur, g[2], pts.size() - g[2]))
	_numeros.append_array(_decaler(g[1], base))
	if _texture:
		_uvs.append_array(_blanc(pts.size()))

## `n` fois le point blanc de la texture.
func _blanc(n: int) -> PackedVector2Array:
	var bloc = _blancs.get(n)
	if bloc == null:
		bloc = PackedVector2Array()
		bloc.resize(n)
		bloc.fill(blanc)
		_blancs[n] = bloc
	return bloc

## Les couleurs d'un gabarit : `plein` fois la couleur, puis `frange` fois la même, transparente.
static func _bloc(couleur: Color, plein: int, frange: int) -> PackedColorArray:
	var par_taille = _blocs.get(couleur)
	if par_taille == null:
		if _blocs.size() >= TEINTES:
			_blocs.clear()
		par_taille = {}
		_blocs[couleur] = par_taille
	var cle := plein * 65536 + frange
	var bloc = par_taille.get(cle)
	if bloc == null:
		bloc = PackedColorArray()
		bloc.resize(plein)
		bloc.fill(couleur)
		var fin := PackedColorArray()
		fin.resize(frange)
		fin.fill(Color(couleur, 0.0))
		bloc.append_array(fin)
		par_taille[cle] = bloc
	return bloc

## Les numéros d'une trame, comptés à partir de `base` (le rang de son premier point dans le lot).
static func _decaler(trame: Array, base: int) -> PackedInt32Array:
	if base == 0:
		return trame[0]
	var numeros = trame[1].get(base)
	if numeros == null:
		numeros = trame[0].duplicate()
		for i in numeros.size():
			numeros[i] += base
		_decalages += 1
		if _decalages > DECALAGES:
			_oublier()
		trame[1][base] = numeros
	return numeros

## Mémoire pleine : tout est oublié d'un coup (les formes qui servent encore sont refaites).
static func _oublier() -> void:
	_decalages = 0
	_neufs = {}
	_vieux = {}
	for trame in _trames.values():
		trame[1].clear()

static func _retrouver(cle: Array):
	var g = _neufs.get(cle)
	if g == null:
		g = _vieux.get(cle)
		if g != null:
			_garder(g[3], g)
	return g

## Garde un gabarit sous sa clé (qui ne doit plus changer : elle porte sa propre copie des points).
static func _garder(cle: Array, g: Array) -> void:
	if _neufs.size() >= MEMOIRE:
		_vieux = _neufs
		_neufs = {}
	g.resize(4)
	g[3] = cle
	_neufs[cle] = g

# ------------------------------------------------------------------ gabarits

static func _cercle_unite() -> PackedVector2Array:
	if _unite.is_empty():
		for i in SEGMENTS + 1:
			_unite.append(Vector2.from_angle(i * TAU / SEGMENTS))
	return _unite

## Disque : 65 points du bord, le centre, puis (lissé) 65 points de frange.
static func _gabarit_disque(r: float, lisse: bool) -> Array:
	var pts: PackedVector2Array = Transform2D(0.0, Vector2(r, r), 0.0, Vector2.ZERO) * _cercle_unite()
	pts.append(Vector2.ZERO)
	if not lisse:
		return [pts, _trame(TRAME_DISQUE_NET), SEGMENTS + 2]
	var dehors := r + PLUME * (r if r < 0.5 else 1.0)
	pts.append_array(Transform2D(0.0, Vector2(dehors, dehors), 0.0, Vector2.ZERO) * _cercle_unite())
	return [pts, _trame(TRAME_DISQUE), SEGMENTS + 2]

## Ligne brisée de `p` : ses deux bords (pleins), puis — lissée — ses deux franges et, si elle
## n'est pas fermée, les huit points de ses deux bouts. Points rangés par blocs de n :
## bord +, bord −, frange +, frange −, bouts.
static func _gabarit_polyligne(p: PackedVector2Array, ep: float, lisse: bool) -> Array:
	return _gabarit_trait(p, ep, lisse, p[0].is_equal_approx(p[p.size() - 1]))

static func _gabarit_trait(p: PackedVector2Array, ep: float, lisse: bool, boucle: bool) -> Array:
	var n := p.size()
	var dirs := _directions(p)
	var ecarts := _ecarts(dirs, boucle)
	var demi := ep * 0.5
	var bord := PLUME * (ep if ep < 1.0 else 1.0)
	var plus := PackedVector2Array()
	var moins := PackedVector2Array()
	var frange_plus := PackedVector2Array()
	var frange_moins := PackedVector2Array()
	for bloc: PackedVector2Array in ([plus, moins, frange_plus, frange_moins] if lisse else [plus, moins]):
		bloc.resize(n)
	for i in n:
		var e: Vector2 = ecarts[i] * demi
		plus[i] = p[i] + e
		moins[i] = p[i] - e
		if lisse:
			var f: Vector2 = ecarts[i] * (demi + bord)
			frange_plus[i] = p[i] + f
			frange_moins[i] = p[i] - f
	var pts := plus.duplicate()
	pts.append_array(moins)
	if lisse:
		pts.append_array(frange_plus)
		pts.append_array(frange_moins)
		if not boucle:
			pts.append_array(_bouts(plus, moins, frange_plus, frange_moins, -dirs[0] * bord, dirs[n - 1] * bord))
	return [pts, _trame_polyligne(n, boucle, lisse), 2 * n]

## Les huit points des bouts d'un trait ouvert : ses quatre points de départ reculés de `d`, ses
## quatre points d'arrivée avancés de `f` (la frange y fait le tour du trait).
static func _bouts(plus: PackedVector2Array, moins: PackedVector2Array, frange_plus: PackedVector2Array, frange_moins: PackedVector2Array, d: Vector2, f: Vector2) -> PackedVector2Array:
	var n := plus.size()
	return PackedVector2Array([
		plus[0] + d, moins[0] + d, frange_plus[0] + d, frange_moins[0] + d,
		plus[n - 1] + f, moins[n - 1] + f, frange_plus[n - 1] + f, frange_moins[n - 1] + f])

## Direction de chaque segment (celle du précédent s'il est de longueur nulle, et pour le dernier point).
static func _directions(p: PackedVector2Array) -> PackedVector2Array:
	var n := p.size()
	var dirs := PackedVector2Array()
	dirs.resize(n)
	var avant := Vector2.ZERO
	for i in n - 1:
		var d := (p[i + 1] - p[i]).normalized()
		if d.is_zero_approx():
			d = avant
		dirs[i] = d
		avant = d
	dirs[n - 1] = avant
	return dirs

## Écart unitaire de chaque point vers le bord « + » du trait : la perpendiculaire aux deux
## bouts d'un trait ouvert, l'onglet entre deux segments ailleurs.
static func _ecarts(dirs: PackedVector2Array, boucle: bool) -> PackedVector2Array:
	var n := dirs.size()
	var premier := Vector2.ZERO
	for d in dirs:
		if not d.is_zero_approx():
			premier = d
			break
	var dernier := dirs[n - 1]
	var ecarts := PackedVector2Array()
	ecarts.resize(n)
	for i in range(1, n - 1):
		ecarts[i] = _onglet(dirs[i], dirs[i - 1])
	if boucle:
		ecarts[0] = _onglet(dirs[0], dernier)
		ecarts[n - 1] = _onglet(dirs[n - 1], premier)
	else:
		ecarts[0] = premier.orthogonal()
		ecarts[n - 1] = dernier.orthogonal()
	return ecarts

## Onglet entre deux segments : la bissectrice, allongée pour garder la largeur du trait
## (au plus trois fois dans un angle aigu). compute_polyline_edge_offset_clamped du moteur.
static func _onglet(seg: Vector2, avant: Vector2) -> Vector2:
	var bissectrice := (avant * seg.length() - seg * avant.length()).normalized()
	var longueur := 1.0
	var sinus := sin(atan2(bissectrice.cross(avant), bissectrice.dot(avant)))
	if not is_zero_approx(sinus) and not seg.is_equal_approx(avant):
		longueur = clampf(1.0 / sinus, -3.0, 3.0)
	else:
		bissectrice = seg.orthogonal()
	if bissectrice.is_zero_approx():
		bissectrice = seg.orthogonal()
	return bissectrice * longueur

# ------------------------------------------------------------------ trames

static func _trame(cle: int) -> Array:
	var trame = _trames.get(cle)
	if trame == null:
		trame = [_numeros_de(cle), {}]
		_trames[cle] = trame
	return trame

static func _numeros_de(cle: int) -> PackedInt32Array:
	var numeros := PackedInt32Array()
	match cle:
		TRAME_TRIANGLE:
			return PackedInt32Array([0, 1, 2])
		TRAME_QUAD:
			return PackedInt32Array([0, 1, 2, 0, 2, 3])
		TRAME_LIGNE:
			for q in [[0, 1, 2, 3], [0, 4, 5, 3], [1, 6, 7, 2], [0, 8, 9, 1], [3, 10, 11, 2], [0, 8, 12, 4], [1, 9, 13, 6], [3, 10, 14, 5], [2, 11, 15, 7]]:
				numeros.append_array(PackedInt32Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
			return numeros
	for i in SEGMENTS:
		numeros.append_array(PackedInt32Array([SEGMENTS + 1, i, i + 1]))
	if cle == TRAME_DISQUE:
		_ruban(numeros, _suite(SEGMENTS + 1, 0, SEGMENTS + 2, [], []))
	return numeros

## Triangles d'un polygone quelconque (ceux du moteur : Geometry2D.triangulate_polygon).
static func _trame_polygone(pts: PackedVector2Array) -> Array:
	if pts.size() == 3:
		return _trame(TRAME_TRIANGLE)
	return [Geometry2D.triangulate_polygon(pts), {}]

## Trame d'une ligne brisée de n points : le trait, puis ses deux franges.
static func _trame_polyligne(n: int, boucle: bool, lisse: bool) -> Array:
	var cle := n * 4 + (2 if boucle else 0) + (1 if lisse else 0)
	var trame = _trames.get(cle)
	if trame != null:
		return trame
	var numeros := PackedInt32Array()
	var bouts := lisse and not boucle
	var c := 4 * n
	_ruban(numeros, _suite(n, 0, n, [c, c + 1] if bouts else [], [c + 4, c + 5] if bouts else []))
	if lisse:
		_ruban(numeros, _suite(n, 0, 2 * n, [c, c + 2] if bouts else [], [n - 1, c + 6, c + 4] if bouts else []))
		_ruban(numeros, _suite(n, n, 3 * n, [c + 1, c + 3] if bouts else [], [2 * n - 1, c + 7, c + 5] if bouts else []))
	trame = [numeros, {}]
	_trames[cle] = trame
	return trame

## Suite de points d'un ruban : `tete`, puis n paires (a + i, b + i), puis `queue`.
static func _suite(n: int, a: int, b: int, tete: Array, queue: Array) -> PackedInt32Array:
	var suite := PackedInt32Array(tete)
	for i in n:
		suite.append(a + i)
		suite.append(b + i)
	suite.append_array(PackedInt32Array(queue))
	return suite

## Les triangles d'un ruban (triangle strip) : chaque point avec les deux suivants.
static func _ruban(numeros: PackedInt32Array, suite: PackedInt32Array) -> void:
	for k in suite.size() - 2:
		numeros.append(suite[k])
		numeros.append(suite[k + 1])
		numeros.append(suite[k + 2])
