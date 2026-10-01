extends Node2D
## Formes passagères : taillades, anneaux d'impact, ondes (Nova, Super, explosion), tourbillon,
## bandes qui frappent, éclairs, pose de mort, et la traînée du dash. Portage de addEffect /
## drawEffects / drawSlash / drawBolt de GAMES/dungeon_666/src/render/fx.mjs.
##
## Une forme naît sur un événement (un petit dictionnaire) ; le dessin, lui, n'alloue rien.
## Cette vue est montée AU-DESSUS du Monde : les ondes de sol sont donc dessinées en trait, avec
## un remplissage très léger, pour ne jamais cacher un télégraphe rouge ni le héros.

const Couleurs = preload("res://jeu/theme/couleurs.gd")

const PLAFOND := 80
const SEGMENTS_ECLAIR := 6
const ECLAIR_ECART := 14.0 # u : débattement d'un éclair
const FANTOMES := 16
const FANTOME_VIE := 0.18 # s
const FANTOME_ALPHA := 0.32
const REMPLI_CHOC := 0.16 # opacité du disque d'une onde de choc (0,35 sur le web, dessiné sous les créatures)
const REMPLI_NOVA := 0.09
const FIL_TAILLADE := 0.16 # part du rayon occupée par le fil net d'une taillade
const CORPS_TAILLADE := 0.22 # opacité du corps de la taillade (0,95 sur le web)
const BORD_NOVA := Color("#fff1d6")
const BORD_CHOC := Color("#ffd0a0")
const BANDE := Color("#ffb08a")

## Position de dessin du héros (posée par Effets à chaque image) : taillades et tourbillon le suivent.
var heros := Vector2.ZERO
var rayon_heros := 14.0

var _formes: Array[Dictionary] = []
var _eclair := PackedVector2Array()
var _fx := PackedFloat32Array()
var _fy := PackedFloat32Array()
var _fvie := PackedFloat32Array()
var _fantome := 0 # prochaine case de l'anneau de fantômes
var _fantomes_vivants := 0
var _vide := true

func _init() -> void:
	_eclair.resize(SEGMENTS_ECLAIR + 1)
	_fx.resize(FANTOMES)
	_fy.resize(FANTOMES)
	_fvie.resize(FANTOMES)
	_fvie.fill(0.0)

func nombre() -> int:
	return _formes.size()

## Ajoute une forme {type, vie, …} ; la plus ancienne cède sa place au plafond.
func ajouter(forme: Dictionary) -> void:
	if _formes.size() >= PLAFOND:
		_formes.pop_front()
	forme["max"] = forme.vie
	_formes.append(forme)

func anneau(x: float, y: float, r0: float, r1: float, couleur: Color, epaisseur: float, vie: float) -> void:
	ajouter({"type": "anneau", "x": x, "y": y, "r0": r0, "r1": r1, "couleur": couleur, "epaisseur": epaisseur, "vie": vie})

## Laisse une image du héros derrière lui (traînée du dash).
func fantome(p: Vector2) -> void:
	_fx[_fantome] = p.x
	_fy[_fantome] = p.y
	_fvie[_fantome] = FANTOME_VIE
	_fantome = (_fantome + 1) % FANTOMES

func vider() -> void:
	_formes.clear()
	_fvie.fill(0.0)
	queue_redraw()

func avancer(dt: float) -> void:
	var i := _formes.size() - 1
	while i >= 0:
		_formes[i].vie -= dt
		if _formes[i].vie <= 0.0:
			_formes.remove_at(i)
		i -= 1
	_fantomes_vivants = 0
	for k in FANTOMES:
		if _fvie[k] > 0.0:
			_fvie[k] -= dt
			_fantomes_vivants += 1
	var vide := _formes.is_empty() and _fantomes_vivants == 0
	if not vide or not _vide:
		queue_redraw()
	_vide = vide

func _draw() -> void:
	_dessiner_fantomes()
	for f in _formes:
		var a: float = f.vie / f.max
		var t := 1.0 - a
		match f.type:
			"taillade": _taillade(f, t, a)
			"anneau": draw_arc(Vector2(f.x, f.y), f.r0 + (f.r1 - f.r0) * t, 0.0, TAU, 40, Color(f.couleur, a), f.epaisseur * a + 0.5, true)
			"choc": _onde(f, f.r * (0.6 + 0.4 * t), a, REMPLI_CHOC, f.get("bord", BORD_CHOC), 4.0)
			"nova": _onde(f, f.r * t, a, REMPLI_NOVA, BORD_NOVA, 5.0)
			"tourbillon": _tourbillon(f, t, a)
			"bande": _bande(f, a)
			"eclair": _dessiner_eclair(f, a)
			"mort": _mort(f, t, a)

func _dessiner_fantomes() -> void:
	if _fantomes_vivants == 0:
		return
	var c: Color = Couleurs.PAL.heroCape
	for k in FANTOMES:
		if _fvie[k] > 0.0:
			draw_circle(Vector2(_fx[k], _fy[k]), rayon_heros * 0.95, Color(c, _fvie[k] / FANTOME_VIE * FANTOME_ALPHA))

## Croissant : l'arc balaie d'un bord à l'autre (dans l'autre sens pour le 2e coup).
func _taillade(f: Dictionary, t: float, a: float) -> void:
	var lourd: bool = f.indice == 2.0 or f.frappe
	var r: float = f.portee * (0.75 + 0.25 * t)
	var sens := -1.0 if f.indice == 1.0 else 1.0
	var a0: float = f.angle - f.arc * 0.5 * sens
	var a1: float = a0 + f.arc * sens * minf(1.0, t * 2.2)
	var dedans := r * (0.45 if lourd else 0.6)
	var points := maxi(6, int(absf(a1 - a0) * 8.0))
	# Un fil net au bout de la lame, un corps translucide derrière : on voit au travers.
	var fil := r * (1.0 - FIL_TAILLADE)
	draw_arc(heros, (fil + dedans) * 0.5, a0, a1, points, Color(f.couleur, a * CORPS_TAILLADE), fil - dedans)
	draw_arc(heros, (r + fil) * 0.5, a0, a1, points, Color(f.couleur, minf(1.0, a * 1.6) * 0.95), r - fil)
	draw_arc(heros, r * 1.03, a0, a1, points, Color(Couleurs.PAL.heroCape, a * 0.35), r * 0.06)

## Onde : disque très léger et bord net (dessinée au-dessus du monde, donc presque vide).
func _onde(f: Dictionary, r: float, a: float, rempli: float, bord: Color, epaisseur: float) -> void:
	if r < 1.0:
		return
	var p := Vector2(f.x, f.y)
	draw_circle(p, r, Color(f.couleur, a * rempli))
	draw_arc(p, r, 0.0, TAU, 48, Color(f.couleur, a * 0.55), epaisseur * a + 3.0, true)
	draw_arc(p, r, 0.0, TAU, 48, Color(bord, a), epaisseur * a * 0.5 + 1.0, true)

func _tourbillon(f: Dictionary, t: float, a: float) -> void:
	var c := Color(Couleurs.PAL.superBar, a * 0.8)
	var a0: float = f.a0 + t * 3.0
	draw_arc(heros, f.r * 0.85, a0, a0 + 2.2, 16, c, 6.0)
	draw_arc(heros, f.r * 0.85, a0 + PI, a0 + PI + 2.2, 16, c, 6.0)

## Bande qui frappe (zone en ligne) : un éclat qui se referme sur son axe.
func _bande(f: Dictionary, a: float) -> void:
	draw_set_transform(Vector2(f.x, f.y), f.angle)
	draw_rect(Rect2(0.0, -f.largeur * 0.5 * a, f.longueur, f.largeur * a), Color(BANDE, a * 0.5))
	draw_set_transform(Vector2.ZERO)

func _dessiner_eclair(f: Dictionary, a: float) -> void:
	var d := Vector2(f.x1 - f.x0, f.y1 - f.y0)
	var travers := d.orthogonal().normalized()
	_eclair[0] = Vector2(f.x0, f.y0)
	for i in range(1, SEGMENTS_ECLAIR):
		var k := float(i) / SEGMENTS_ECLAIR
		_eclair[i] = _eclair[0] + d * k + travers * (_hasard(f.graine + i) * ECLAIR_ECART)
	_eclair[SEGMENTS_ECLAIR] = Vector2(f.x1, f.y1)
	draw_polyline(_eclair, Color(f.couleur, a * 0.55), 5.0)
	draw_polyline(_eclair, Color(1.0, 1.0, 1.0, a), 1.5)

## Nombre pseudo-aléatoire stable dans [-1, 1] (l'éclair garde sa forme pendant sa courte vie).
static func _hasard(graine: float) -> float:
	return fposmod(sin(graine * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0

## Pose de mort : la silhouette blanchit puis se rétracte (pas de disparition sèche).
func _mort(f: Dictionary, t: float, a: float) -> void:
	var c: Color = Couleurs.PAL.impactRing if t < 0.35 else f.couleur
	draw_circle(Vector2(f.x, f.y), maxf(0.5, f.r * (1.0 + 0.3 * t) * (1.0 - t * t)), Color(c, a))
