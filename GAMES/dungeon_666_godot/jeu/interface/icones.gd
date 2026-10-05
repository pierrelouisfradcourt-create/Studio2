extends RefCounted
## Pictogrammes des commandes, DESSINÉS (aucune image) : portage des `ICONS` de
## GAMES/dungeon_666/src/render/hud.mjs. Les noms sont ceux du champ `icon` des kits
## (data/classes.json) et, par défaut, l'identifiant du bouton (attack, dash, skill, gadget, super).
## Le bouton de DÉPLACEMENT porte le geste de la classe (data/classes.json, `moves` : dash, saut, roulade).
##   Icones.dessiner(self, "axe", centre, rayon, couleur)   dans le `_draw` d'un CanvasItem
##   Icones.ajouter(lot, "axe", centre, rayon, couleur)     dans un lot de triangles déjà ouvert
## Coût : un pictogramme part en UN appel de dessin (jeu/theme/triangles.gd), ou avec le lot de
## celui qui le dessine.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const PAS := 8 # segments par courbe
const NOMS := ["attack", "dash", "saut", "roulade", "skill", "gadget", "super", "daggers", "axe", "hammer", "bow", "crossbow", "chain", "leap", "fire", "fan", "bomb", "trap", "roar", "totem", "sentence", "rain", "forme", "meute", "ruee", "burst", "sillage", "stigmate", "riposte", "faille", "hachette", "garde", "proie", "leurre", "trait", "ombre", "grace", "grele"]

static func connue(nom) -> bool:
	return nom is String and nom in NOMS

## Dessine le pictogramme `nom` centré en `c`, à l'échelle du bouton de rayon `r`.
static func dessiner(ci: CanvasItem, nom: String, c: Vector2, r: float, col: Color) -> void:
	var lot := Triangles.new()
	ajouter(lot, nom, c, r, col)
	lot.tracer(ci)

## Ajoute le pictogramme `nom` au lot (repère du lot : celui de qui le dessine).
static func ajouter(lot: Triangles, nom: String, c: Vector2, r: float, col: Color) -> void:
	var avant := lot.repere
	lot.repere = avant * Transform2D(0.0, c)
	c = avant * c
	match nom:
		"attack": _epee(lot, c, r, col)
		"dash": _dash(lot, r, col)
		"saut": _saut(lot, r, col)
		"roulade": _roulade(lot, r, col)
		"skill": _lance(lot, c, r, col)
		"gadget": _nova(lot, r, col)
		"super": _colere(lot, r, col)
		"daggers": _dagues(lot, c, r, col)
		"axe": _hache(lot, c, r, col)
		"hammer": _marteau(lot, c, r, col)
		"bow": _arc(lot, r, col)
		"crossbow": _arbalete(lot, r, col)
		"chain": _chaine(lot, r, col)
		"leap": _bond(lot, r, col)
		"fire": _feu(lot, r, col)
		"fan": _eventail(lot, c, r, col)
		"bomb": _bombe(lot, r, col)
		"trap": _piege(lot, r, col)
		"roar": _cri(lot, r, col)
		"totem": _totem(lot, r, col)
		"sentence": _sentence(lot, r, col)
		"forme": _spectre(lot, r, col)
		"meute": _meute(lot, r, col)
		"ruee": _ruee(lot, r, col)
		"burst": _embrasement(lot, r, col)
		"rain": _nuee(lot, c, r, col)
		"sillage": _sillage(lot, r, col)
		"stigmate": _stigmate(lot, r, col)
		"riposte": _riposte(lot, c, r, col)
		"faille": _faille(lot, r, col)
		"hachette": _hachette(lot, c, r, col)
		"garde": _garde(lot, r, col)
		"proie": _proie(lot, r, col)
		"leurre": _leurre(lot, r, col)
		"trait": _trait(lot, r, col)
		"ombre": _ombre(lot, r, col)
		"grace": _grace(lot, c, r, col)
		"grele": _grele(lot, r, col)
	lot.repere = avant

# ---------------------------------------------------------------- outils de tracé

## Repère d'un pictogramme tourné : `c` est le centre du bouton, déjà dans le repère de l'écran.
static func _place(c: Vector2, rotation: float = 0.0) -> Transform2D:
	return Transform2D(rotation, c)

static func _rect(lot: Triangles, r: float, x: float, y: float, w: float, h: float, col: Color) -> void:
	lot.rect(Rect2(x * r, y * r, w * r, h * r), col)

## Polygone plein dont les sommets sont donnés en fractions du rayon.
static func _poly(lot: Triangles, r: float, sommets: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for s in sommets:
		pts.append(Vector2(s[0], s[1]) * r)
	lot.polygone(pts, col)

## Prolonge `pts` par une courbe quadratique (contrôle `p1`, arrivée `p2`), sans le point de départ.
static func _courbe(pts: PackedVector2Array, p1: Vector2, p2: Vector2) -> void:
	var p0 := pts[pts.size() - 1]
	for i in range(1, PAS + 1):
		var t := float(i) / PAS
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))

## Forme fermée faite de courbes : [[départ], [contrôle, arrivée], …], en fractions du rayon.
static func _forme(lot: Triangles, r: float, depart: Vector2, courbes: Array, col: Color) -> void:
	var pts := PackedVector2Array([depart * r])
	for k in courbes:
		_courbe(pts, k[0] * r, k[1] * r)
	if pts[pts.size() - 1].is_equal_approx(pts[0]):
		pts.remove_at(pts.size() - 1)
	lot.polygone(pts, col)

static func _ellipse(lot: Triangles, centre: Vector2, rayons: Vector2, rot: float, col: Color, epaisseur: float) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * i / 20.0
		pts.append(centre + Vector2(cos(a) * rayons.x, sin(a) * rayons.y).rotated(rot))
	lot.polyligne(pts, col, epaisseur)

# ---------------------------------------------------------------- boutons par défaut

static func _epee(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	lot.repere = _place(c, -PI / 4.0)
	_rect(lot, r, -0.09, -0.55, 0.18, 0.8, col)
	_rect(lot, r, -0.3, 0.22, 0.6, 0.1, col)
	_rect(lot, r, -0.07, 0.3, 0.14, 0.22, col)

static func _dash(lot: Triangles, r: float, col: Color) -> void:
	for o in [-0.22, 0.12]:
		_poly(lot, r, [[o - 0.1, -0.35], [o + 0.22, 0.0], [o - 0.1, 0.35], [o, 0.0]], col)

## Le saut du Bourreau : les chevrons du dash, dressés vers le haut, au-dessus du sol.
static func _saut(lot: Triangles, r: float, col: Color) -> void:
	for o in [-0.22, 0.1]:
		_poly(lot, r, [[-0.35, o + 0.1], [0.0, o - 0.22], [0.35, o + 0.1], [0.0, o]], col)
	_rect(lot, r, -0.45, 0.4, 0.9, 0.09, col)

## La roulade de la Chasseresse : une boucle qui roule vers la droite, au ras du sol.
static func _roulade(lot: Triangles, r: float, col: Color) -> void:
	var centre := Vector2(0.0, -0.08) * r
	var fin := -PI * 0.15
	lot.arc(centre, r * 0.34, fin - PI * 1.5, fin, 18, col, r * 0.11)
	var bout := centre + Vector2.from_angle(fin) * r * 0.34
	var sens := Vector2.from_angle(fin + PI / 2.0)
	var cote := Vector2.from_angle(fin) * r * 0.2
	lot.polygone(PackedVector2Array([bout + sens * r * 0.3, bout + cote, bout - cote]), col)
	_rect(lot, r, -0.45, 0.42, 0.9, 0.08, col)

static func _lance(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	lot.repere = _place(c, -PI / 4.0)
	_rect(lot, r, -0.05, -0.5, 0.1, 1.0, col)
	_poly(lot, r, [[0.0, -0.62], [0.16, -0.38], [-0.16, -0.38]], col)

static func _nova(lot: Triangles, r: float, col: Color) -> void:
	var cote := r * 0.15
	for i in range(8):
		var p := Vector2.from_angle(TAU * i / 8.0) * r * 0.3
		lot.rect(Rect2(p - Vector2.ONE * cote / 2.0, Vector2.ONE * cote), col)
	lot.disque(Vector2.ZERO, r * 0.18, col)

static func _colere(lot: Triangles, r: float, col: Color) -> void:
	_forme(lot, r, Vector2(0.0, -0.5), [
		[Vector2(0.45, -0.05), Vector2(0.2, 0.45)],
		[Vector2(0.0, 0.2), Vector2(-0.2, 0.45)],
		[Vector2(-0.45, -0.05), Vector2(0.0, -0.5)],
	], col)

# ---------------------------------------------------------------- armes

static func _dagues(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	for s in [-1.0, 1.0]:
		lot.repere = _place(c, s * PI / 5.0)
		_rect(lot, r, -0.06, -0.5, 0.12, 0.55, col)
		_rect(lot, r, -0.18, 0.05, 0.36, 0.08, col)
		_rect(lot, r, -0.05, 0.13, 0.1, 0.2, col)

static func _hache(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	lot.repere = _place(c, -PI / 4.0)
	_rect(lot, r, -0.05, -0.5, 0.1, 1.0, col)
	var pts := PackedVector2Array([Vector2(0.05, -0.45) * r])
	_courbe(pts, Vector2(0.55, -0.35) * r, Vector2(0.45, 0.05) * r)
	pts.append(Vector2(0.05, -0.1) * r)
	lot.polygone(pts, col)

static func _marteau(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	lot.repere = _place(c, -PI / 4.0)
	_rect(lot, r, -0.05, -0.3, 0.1, 0.85, col)
	_rect(lot, r, -0.36, -0.55, 0.72, 0.3, col)

static func _arc(lot: Triangles, r: float, col: Color) -> void:
	var centre := Vector2(-0.25 * r, 0.0)
	lot.arc(centre, r * 0.55, -1.1, 1.1, 16, col, r * 0.1)
	lot.ligne(centre + Vector2.from_angle(1.1) * r * 0.55, centre + Vector2.from_angle(-1.1) * r * 0.55, col, maxf(1.0, r * 0.04))
	_rect(lot, r, -0.3, -0.035, 0.75, 0.07, col)
	_poly(lot, r, [[0.55, 0.0], [0.38, -0.12], [0.38, 0.12]], col)

static func _arbalete(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.45, -0.06, 0.9, 0.12, col)
	lot.arc(Vector2(0.05, 0.45) * r, r * 0.55, -PI * 0.8, -PI * 0.2, 16, col, r * 0.1)
	_poly(lot, r, [[0.55, 0.0], [0.38, -0.13], [0.38, 0.13]], col)

# ---------------------------------------------------------------- compétences

static func _chaine(lot: Triangles, r: float, col: Color) -> void:
	for i in range(3):
		_ellipse(lot, Vector2(-0.36 + i * 0.3, 0.2 - i * 0.2) * r, Vector2(0.17, 0.1) * r, -PI / 4.0, col, r * 0.09)
	lot.arc(Vector2(0.38, -0.3) * r, r * 0.2, PI * 0.9, PI * 2.1, 14, col, r * 0.09)

static func _bond(lot: Triangles, r: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(-0.5, 0.3) * r])
	_courbe(pts, Vector2(0.0, -0.75) * r, Vector2(0.4, 0.15) * r)
	lot.polyligne(pts, col, r * 0.1)
	_poly(lot, r, [[0.5, 0.35], [0.22, 0.18], [0.5, 0.02]], col)
	_rect(lot, r, -0.55, 0.42, 1.1, 0.08, col)

static func _feu(lot: Triangles, r: float, col: Color) -> void:
	_forme(lot, r, Vector2(0.0, -0.55), [
		[Vector2(0.5, -0.1), Vector2(0.3, 0.35)],
		[Vector2(0.15, 0.5), Vector2(0.0, 0.5)],
		[Vector2(-0.15, 0.5), Vector2(-0.3, 0.35)],
		[Vector2(-0.45, 0.0), Vector2(-0.1, -0.2)],
		[Vector2(-0.05, -0.35), Vector2(0.0, -0.55)],
	], col)

static func _eventail(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	for i in range(5):
		lot.repere = _place(c, -PI / 2.0 + (i - 2) * 0.32)
		_rect(lot, r, 0.0, -0.035, 0.55, 0.07, col)
		_poly(lot, r, [[0.62, 0.0], [0.48, -0.09], [0.48, 0.09]], col)

# ---------------------------------------------------------------- gadgets

static func _bombe(lot: Triangles, r: float, col: Color) -> void:
	lot.disque(Vector2(-0.05, 0.1) * r, r * 0.36, col)
	_rect(lot, r, 0.12, -0.38, 0.14, 0.2, col)
	lot.disque(Vector2(0.32, -0.48) * r, r * 0.09, col)

static func _piege(lot: Triangles, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		pts.append(Vector2(0.0, 0.1 * r) + Vector2.from_angle(PI + PI * i / 12.0) * r * 0.45)
	pts.append(Vector2(0.45, 0.18) * r)
	pts.append(Vector2(-0.45, 0.18) * r)
	lot.polygone(pts, col)
	var sombre := Color(Couleurs.UI.panel, 0.9)
	for i in range(4):
		var x := -0.3 + i * 0.2
		_poly(lot, r, [[x - 0.07, 0.1], [x, -0.12], [x + 0.07, 0.1]], sombre)

static func _cri(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[-0.5, -0.2], [-0.05, -0.05], [-0.5, 0.2]], col)
	for i in range(3):
		lot.arc(Vector2(-0.15 * r, 0.0), r * (0.28 + i * 0.16), -0.7, 0.7, 12, col, r * 0.08)

static func _totem(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[0.0, -0.55], [0.2, -0.15], [0.12, 0.45], [-0.12, 0.45], [-0.2, -0.15]], col)
	_ellipse(lot, Vector2(0.0, 0.45 * r), Vector2(0.5, 0.14) * r, 0.0, col, maxf(1.0, r * 0.05))

# ---------------------------------------------------------------- Supers

static func _sentence(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.05, -0.55, 0.1, 0.5, col)
	var pts := PackedVector2Array([Vector2(-0.4, -0.1) * r, Vector2(0.4, -0.1) * r])
	_courbe(pts, Vector2(0.45, 0.35) * r, Vector2(0.0, 0.5) * r)
	_courbe(pts, Vector2(-0.45, 0.35) * r, Vector2(-0.4, -0.1) * r)
	pts.remove_at(pts.size() - 1)
	lot.polygone(pts, col)

# ---------------------------------------------------------------- ultimes de classe (combat V3, étape 2)

## Forme du Damné : une flamme à deux yeux — le spectre de braise.
static func _spectre(lot: Triangles, r: float, col: Color) -> void:
	_poly(lot, r, [[0.0, -0.6], [0.2, -0.22], [0.42, -0.34], [0.46, 0.14], [0.26, 0.5], [-0.26, 0.5], [-0.46, 0.14], [-0.42, -0.34], [-0.2, -0.22]], col)
	var sombre := Color(Couleurs.UI.panel, 0.9)
	for x: float in [-0.17, 0.17]:
		_poly(lot, r, [[x - 0.1, 0.02], [x + 0.1, 0.08], [x, 0.24]], sombre)

## Meute des Limbes : une empreinte de limier — un coussinet, trois doigts griffus.
static func _meute(lot: Triangles, r: float, col: Color) -> void:
	lot.disque(Vector2(0.0, 0.22) * r, r * 0.27, col)
	for d in [[-0.33, -0.1], [0.0, -0.3], [0.33, -0.1]]:
		lot.disque(Vector2(d[0], d[1]) * r, r * 0.13, col)
		_poly(lot, r, [[d[0] - 0.06, d[1] - 0.1], [d[0] + 0.06, d[1] - 0.1], [d[0], d[1] - 0.3]], col)

## Ruée spectrale : une pointe qui traverse, deux traits de vitesse.
static func _ruee(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.55, -0.06, 0.75, 0.12, col)
	_poly(lot, r, [[0.58, 0.0], [0.12, -0.34], [0.22, 0.0], [0.12, 0.34]], col)
	_rect(lot, r, -0.5, -0.34, 0.36, 0.08, col)
	_rect(lot, r, -0.5, 0.26, 0.36, 0.08, col)

## Embrasement : un éclat à huit pointes — l'explosion qui met fin à la forme.
static func _embrasement(lot: Triangles, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(16):
		pts.append(Vector2.from_angle(i * TAU / 16.0 - PI / 2.0) * r * (0.58 if i % 2 == 0 else 0.24))
	lot.polygone(pts, col)

static func _nuee(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	for p in [[-0.3, -0.2], [0.0, 0.05], [0.3, -0.2], [-0.15, 0.35], [0.15, 0.35]]:
		lot.repere = _place(c + Vector2(p[0], p[1]) * r, PI / 2.0)
		_rect(lot, r, -0.25, -0.03, 0.35, 0.06, col)
		_poly(lot, r, [[0.18, 0.0], [0.08, -0.08], [0.08, 0.08]], col)

# ---------------------------------------------------------------- compétences neuves (combat V3, étape 4)

## Sillage de braise : trois flammes qui grandissent le long d'une traînée au sol.
static func _sillage(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.55, 0.38, 1.1, 0.08, col)
	for f in [[-0.38, 0.2], [-0.02, 0.32], [0.36, 0.46]]:
		var x: float = f[0]
		var h: float = f[1]
		_poly(lot, r, [[x, 0.34 - h * 1.9], [x + h * 0.55, 0.14], [x + h * 0.3, 0.34], [x - h * 0.3, 0.34], [x - h * 0.5, 0.1]], col)

## Stigmate : le fer à marquer — un anneau, une pointe vers le bas, trois dents autour.
static func _stigmate(lot: Triangles, r: float, col: Color) -> void:
	_ellipse(lot, Vector2.ZERO, Vector2(0.36, 0.36) * r, 0.0, col, r * 0.1)
	_poly(lot, r, [[-0.2, -0.14], [0.2, -0.14], [0.0, 0.22]], col)
	for i in range(3):
		var d := Vector2.from_angle(-PI / 2.0 + i * TAU / 3.0)
		var t := d.orthogonal()
		lot.polygone(PackedVector2Array([d * r * 0.62, d * r * 0.4 + t * r * 0.11, d * r * 0.4 - t * r * 0.11]), col)

## Contre-taille : deux lames croisées — celle qui pare, celle qui rend.
static func _riposte(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	for s: float in [-1.0, 1.0]:
		lot.repere = _place(c, s * PI / 4.0)
		_rect(lot, r, -0.07, -0.58, 0.14, 0.86, col)
		_poly(lot, r, [[-0.07, -0.58], [0.07, -0.58], [0.0, -0.72]], col)
		_rect(lot, r, -0.2, 0.26, 0.4, 0.08, col)
		_rect(lot, r, -0.05, 0.34, 0.1, 0.2, col)

## Faille : le sol (un trait) fendu par une lézarde en zigzag, deux éclats qui sautent.
static func _faille(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.58, 0.3, 0.42, 0.09, col)
	_rect(lot, r, 0.16, 0.3, 0.42, 0.09, col)
	_poly(lot, r, [[-0.16, 0.3], [0.02, -0.02], [-0.1, -0.06], [0.1, -0.5], [0.2, -0.1], [0.06, -0.06], [0.16, 0.3], [0.0, 0.52]], col)
	_poly(lot, r, [[-0.44, 0.1], [-0.3, -0.12], [-0.24, 0.12]], col)
	_poly(lot, r, [[0.34, 0.06], [0.48, -0.16], [0.52, 0.12]], col)

## Hache du supplice : la hache, et la flèche courbe de son retour.
static func _hachette(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	lot.arc(Vector2(0.0, 0.05) * r, r * 0.52, PI * 0.15, PI * 1.05, 16, col, r * 0.09)
	_poly(lot, r, [[-0.62, -0.02], [-0.38, -0.02], [-0.5, -0.24]], col)
	lot.repere = _place(c + Vector2(0.06, -0.06) * r, -PI / 4.0)
	_rect(lot, r, -0.045, -0.4, 0.09, 0.78, col)
	var pts := PackedVector2Array([Vector2(0.045, -0.38) * r])
	_courbe(pts, Vector2(0.48, -0.3) * r, Vector2(0.4, 0.04) * r)
	pts.append(Vector2(0.045, -0.08) * r)
	lot.polygone(pts, col)

## Garde de fer : un écu, sa nervure en creux.
static func _garde(lot: Triangles, r: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(-0.42, -0.48) * r, Vector2(0.42, -0.48) * r, Vector2(0.42, 0.0) * r])
	_courbe(pts, Vector2(0.38, 0.4) * r, Vector2(0.0, 0.58) * r)
	_courbe(pts, Vector2(-0.38, 0.4) * r, Vector2(-0.42, 0.0) * r)
	lot.polygone(pts, col)
	var sombre := Color(Couleurs.UI.panel, 0.9)
	_rect(lot, r, -0.05, -0.36, 0.1, 0.72, sombre)
	_rect(lot, r, -0.28, -0.2, 0.56, 0.1, sombre)

## Marque de la proie : un réticule — quatre crochets, un point au centre.
static func _proie(lot: Triangles, r: float, col: Color) -> void:
	for i in range(4):
		var a := PI / 4.0 + i * PI / 2.0
		lot.arc(Vector2.ZERO, r * 0.46, a - 0.5, a + 0.5, 8, col, r * 0.11)
	for d in [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]]:
		_rect(lot, r, d[0] * 0.56 - 0.04, d[1] * 0.56 - 0.04, 0.08, 0.08, col)
	lot.disque(Vector2.ZERO, r * 0.12, col)

## Leurre d'os : un épouvantail — pieu, traverse, crâne, haillons.
static func _leurre(lot: Triangles, r: float, col: Color) -> void:
	_rect(lot, r, -0.05, -0.2, 0.1, 0.78, col)
	_rect(lot, r, -0.5, -0.12, 1.0, 0.1, col)
	lot.disque(Vector2(0.0, -0.36) * r, r * 0.2, col)
	for s: float in [-1.0, 1.0]:
		_poly(lot, r, [[s * 0.46, -0.04], [s * 0.2, -0.04], [s * 0.36, 0.32]], col)
	var sombre := Color(Couleurs.UI.panel, 0.9)
	for x: float in [-0.08, 0.08]:
		lot.disque(Vector2(x, -0.38) * r, r * 0.045, sombre)

## Trait de Nemrod : un arc bandé à fond, sa longue flèche prête à partir.
static func _trait(lot: Triangles, r: float, col: Color) -> void:
	var centre := Vector2(0.1 * r, 0.0)
	lot.arc(centre, r * 0.5, -1.25, 1.25, 16, col, r * 0.1)
	var haut := centre + Vector2.from_angle(-1.25) * r * 0.5
	var bas := centre + Vector2.from_angle(1.25) * r * 0.5
	var corde := Vector2(-0.5 * r, 0.0)
	lot.ligne(haut, corde, col, maxf(1.0, r * 0.045))
	lot.ligne(bas, corde, col, maxf(1.0, r * 0.045))
	_rect(lot, r, -0.5, -0.04, 1.0, 0.08, col)
	_poly(lot, r, [[0.66, 0.0], [0.42, -0.15], [0.42, 0.15]], col)

## Ombre jumelle (étape 5) : deux silhouettes côte à côte — la sienne, pleine, et son ombre, en contour.
static func _ombre(lot: Triangles, r: float, col: Color) -> void:
	lot.disque(Vector2(-0.22, -0.3) * r, r * 0.17, col)
	_poly(lot, r, [[-0.42, -0.08], [-0.02, -0.08], [-0.1, 0.5], [-0.34, 0.5]], col)
	lot.arc(Vector2(0.28, -0.3) * r, r * 0.15, 0.0, TAU, 14, col, maxf(1.0, r * 0.06))
	var ep := maxf(1.0, r * 0.06)
	var pts := [Vector2(0.08, -0.08), Vector2(0.48, -0.08), Vector2(0.4, 0.5), Vector2(0.16, 0.5)]
	for i in 4:
		lot.ligne(pts[i] * r, pts[(i + 1) % 4] * r, col, ep)

## Décollation (étape 5) : la hache qui tombe droit sur le billot — un fer large, un manche, le trait du sol.
static func _grace(lot: Triangles, c: Vector2, r: float, col: Color) -> void:
	_rect(lot, r, -0.5, 0.46, 1.0, 0.09, col)
	_rect(lot, r, -0.26, 0.24, 0.52, 0.16, col)
	lot.repere = _place(c + Vector2(0.0, -0.12) * r, PI * 0.12)
	_rect(lot, r, -0.045, -0.46, 0.09, 0.62, col)
	var pts := PackedVector2Array([Vector2(-0.045, -0.02) * r])
	_courbe(pts, Vector2(-0.5, 0.02) * r, Vector2(-0.42, 0.34) * r)
	pts.append(Vector2(0.0, 0.2) * r)
	_courbe(pts, Vector2(0.42, 0.34) * r, Vector2(0.5, 0.02) * r)
	pts.append(Vector2(0.045, -0.02) * r)
	lot.polygone(pts, col)

## Grêle des Limbes (étape 5) : trois traits qui tombent, pointe en bas, sur un cercle au sol.
static func _grele(lot: Triangles, r: float, col: Color) -> void:
	_ellipse(lot, Vector2(0.0, 0.42) * r, Vector2(0.56, 0.16) * r, 0.0, col, maxf(1.0, r * 0.07))
	for x: float in [-0.32, 0.0, 0.32]:
		var haut: float = -0.56 + absf(x) * 0.5
		_rect(lot, r, x - 0.035, haut, 0.07, 0.6, col)
		_poly(lot, r, [[x, haut + 0.82], [x - 0.13, haut + 0.56], [x + 0.13, haut + 0.56]], col)
