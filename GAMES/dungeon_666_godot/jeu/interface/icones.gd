extends RefCounted
## Pictogrammes des commandes, DESSINÉS (aucune image) : portage des `ICONS` de
## GAMES/dungeon_666/src/render/hud.mjs. Les noms sont ceux du champ `icon` des kits
## (data/classes.json) et, par défaut, l'identifiant du bouton (attack, dash, skill, gadget, super).
##   Icones.dessiner(self, "axe", centre, rayon, couleur)   dans le `_draw` d'un CanvasItem

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const PAS := 8 # segments par courbe
const NOMS := ["attack", "dash", "skill", "gadget", "super", "daggers", "axe", "hammer", "bow", "crossbow", "chain", "leap", "fire", "fan", "bomb", "trap", "roar", "totem", "sentence", "rain"]

static func connue(nom) -> bool:
	return nom is String and nom in NOMS

## Dessine le pictogramme `nom` centré en `c`, à l'échelle du bouton de rayon `r`.
static func dessiner(ci: CanvasItem, nom: String, c: Vector2, r: float, col: Color) -> void:
	ci.draw_set_transform(c)
	match nom:
		"attack": _epee(ci, c, r, col)
		"dash": _dash(ci, r, col)
		"skill": _lance(ci, c, r, col)
		"gadget": _nova(ci, r, col)
		"super": _colere(ci, r, col)
		"daggers": _dagues(ci, c, r, col)
		"axe": _hache(ci, c, r, col)
		"hammer": _marteau(ci, c, r, col)
		"bow": _arc(ci, r, col)
		"crossbow": _arbalete(ci, r, col)
		"chain": _chaine(ci, r, col)
		"leap": _bond(ci, r, col)
		"fire": _feu(ci, r, col)
		"fan": _eventail(ci, c, r, col)
		"bomb": _bombe(ci, r, col)
		"trap": _piege(ci, r, col)
		"roar": _cri(ci, r, col)
		"totem": _totem(ci, r, col)
		"sentence": _sentence(ci, r, col)
		"rain": _nuee(ci, c, r, col)
	ci.draw_set_transform(Vector2.ZERO)

# ---------------------------------------------------------------- outils de tracé

static func _rect(ci: CanvasItem, r: float, x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(x * r, y * r, w * r, h * r), col)

## Polygone plein dont les sommets sont donnés en fractions du rayon.
static func _poly(ci: CanvasItem, r: float, sommets: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for s in sommets:
		pts.append(Vector2(s[0], s[1]) * r)
	ci.draw_colored_polygon(pts, col)

## Prolonge `pts` par une courbe quadratique (contrôle `p1`, arrivée `p2`), sans le point de départ.
static func _courbe(pts: PackedVector2Array, p1: Vector2, p2: Vector2) -> void:
	var p0 := pts[pts.size() - 1]
	for i in range(1, PAS + 1):
		var t := float(i) / PAS
		pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))

## Forme fermée faite de courbes : [[départ], [contrôle, arrivée], …], en fractions du rayon.
static func _forme(ci: CanvasItem, r: float, depart: Vector2, courbes: Array, col: Color) -> void:
	var pts := PackedVector2Array([depart * r])
	for k in courbes:
		_courbe(pts, k[0] * r, k[1] * r)
	if pts[pts.size() - 1].is_equal_approx(pts[0]):
		pts.remove_at(pts.size() - 1)
	ci.draw_colored_polygon(pts, col)

static func _ellipse(ci: CanvasItem, centre: Vector2, rayons: Vector2, rot: float, col: Color, epaisseur: float) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * i / 20.0
		pts.append(centre + Vector2(cos(a) * rayons.x, sin(a) * rayons.y).rotated(rot))
	ci.draw_polyline(pts, col, epaisseur, true)

# ---------------------------------------------------------------- boutons par défaut

static func _epee(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_set_transform(c, -PI / 4.0)
	_rect(ci, r, -0.09, -0.55, 0.18, 0.8, col)
	_rect(ci, r, -0.3, 0.22, 0.6, 0.1, col)
	_rect(ci, r, -0.07, 0.3, 0.14, 0.22, col)

static func _dash(ci: CanvasItem, r: float, col: Color) -> void:
	for o in [-0.22, 0.12]:
		_poly(ci, r, [[o - 0.1, -0.35], [o + 0.22, 0.0], [o - 0.1, 0.35], [o, 0.0]], col)

static func _lance(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_set_transform(c, -PI / 4.0)
	_rect(ci, r, -0.05, -0.5, 0.1, 1.0, col)
	_poly(ci, r, [[0.0, -0.62], [0.16, -0.38], [-0.16, -0.38]], col)

static func _nova(ci: CanvasItem, r: float, col: Color) -> void:
	var cote := r * 0.15
	for i in range(8):
		var p := Vector2.from_angle(TAU * i / 8.0) * r * 0.3
		ci.draw_rect(Rect2(p - Vector2.ONE * cote / 2.0, Vector2.ONE * cote), col)
	ci.draw_circle(Vector2.ZERO, r * 0.18, col, true, -1.0, true)

static func _colere(ci: CanvasItem, r: float, col: Color) -> void:
	_forme(ci, r, Vector2(0.0, -0.5), [
		[Vector2(0.45, -0.05), Vector2(0.2, 0.45)],
		[Vector2(0.0, 0.2), Vector2(-0.2, 0.45)],
		[Vector2(-0.45, -0.05), Vector2(0.0, -0.5)],
	], col)

# ---------------------------------------------------------------- armes

static func _dagues(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for s in [-1.0, 1.0]:
		ci.draw_set_transform(c, s * PI / 5.0)
		_rect(ci, r, -0.06, -0.5, 0.12, 0.55, col)
		_rect(ci, r, -0.18, 0.05, 0.36, 0.08, col)
		_rect(ci, r, -0.05, 0.13, 0.1, 0.2, col)

static func _hache(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_set_transform(c, -PI / 4.0)
	_rect(ci, r, -0.05, -0.5, 0.1, 1.0, col)
	var pts := PackedVector2Array([Vector2(0.05, -0.45) * r])
	_courbe(pts, Vector2(0.55, -0.35) * r, Vector2(0.45, 0.05) * r)
	pts.append(Vector2(0.05, -0.1) * r)
	ci.draw_colored_polygon(pts, col)

static func _marteau(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_set_transform(c, -PI / 4.0)
	_rect(ci, r, -0.05, -0.3, 0.1, 0.85, col)
	_rect(ci, r, -0.36, -0.55, 0.72, 0.3, col)

static func _arc(ci: CanvasItem, r: float, col: Color) -> void:
	var centre := Vector2(-0.25 * r, 0.0)
	ci.draw_arc(centre, r * 0.55, -1.1, 1.1, 16, col, r * 0.1, true)
	ci.draw_line(centre + Vector2.from_angle(1.1) * r * 0.55, centre + Vector2.from_angle(-1.1) * r * 0.55, col, maxf(1.0, r * 0.04), true)
	_rect(ci, r, -0.3, -0.035, 0.75, 0.07, col)
	_poly(ci, r, [[0.55, 0.0], [0.38, -0.12], [0.38, 0.12]], col)

static func _arbalete(ci: CanvasItem, r: float, col: Color) -> void:
	_rect(ci, r, -0.45, -0.06, 0.9, 0.12, col)
	ci.draw_arc(Vector2(0.05, 0.45) * r, r * 0.55, -PI * 0.8, -PI * 0.2, 16, col, r * 0.1, true)
	_poly(ci, r, [[0.55, 0.0], [0.38, -0.13], [0.38, 0.13]], col)

# ---------------------------------------------------------------- compétences

static func _chaine(ci: CanvasItem, r: float, col: Color) -> void:
	for i in range(3):
		_ellipse(ci, Vector2(-0.36 + i * 0.3, 0.2 - i * 0.2) * r, Vector2(0.17, 0.1) * r, -PI / 4.0, col, r * 0.09)
	ci.draw_arc(Vector2(0.38, -0.3) * r, r * 0.2, PI * 0.9, PI * 2.1, 14, col, r * 0.09, true)

static func _bond(ci: CanvasItem, r: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(-0.5, 0.3) * r])
	_courbe(pts, Vector2(0.0, -0.75) * r, Vector2(0.4, 0.15) * r)
	ci.draw_polyline(pts, col, r * 0.1, true)
	_poly(ci, r, [[0.5, 0.35], [0.22, 0.18], [0.5, 0.02]], col)
	_rect(ci, r, -0.55, 0.42, 1.1, 0.08, col)

static func _feu(ci: CanvasItem, r: float, col: Color) -> void:
	_forme(ci, r, Vector2(0.0, -0.55), [
		[Vector2(0.5, -0.1), Vector2(0.3, 0.35)],
		[Vector2(0.15, 0.5), Vector2(0.0, 0.5)],
		[Vector2(-0.15, 0.5), Vector2(-0.3, 0.35)],
		[Vector2(-0.45, 0.0), Vector2(-0.1, -0.2)],
		[Vector2(-0.05, -0.35), Vector2(0.0, -0.55)],
	], col)

static func _eventail(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for i in range(5):
		ci.draw_set_transform(c, -PI / 2.0 + (i - 2) * 0.32)
		_rect(ci, r, 0.0, -0.035, 0.55, 0.07, col)
		_poly(ci, r, [[0.62, 0.0], [0.48, -0.09], [0.48, 0.09]], col)

# ---------------------------------------------------------------- gadgets

static func _bombe(ci: CanvasItem, r: float, col: Color) -> void:
	ci.draw_circle(Vector2(-0.05, 0.1) * r, r * 0.36, col, true, -1.0, true)
	_rect(ci, r, 0.12, -0.38, 0.14, 0.2, col)
	ci.draw_circle(Vector2(0.32, -0.48) * r, r * 0.09, col, true, -1.0, true)

static func _piege(ci: CanvasItem, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		pts.append(Vector2(0.0, 0.1 * r) + Vector2.from_angle(PI + PI * i / 12.0) * r * 0.45)
	pts.append(Vector2(0.45, 0.18) * r)
	pts.append(Vector2(-0.45, 0.18) * r)
	ci.draw_colored_polygon(pts, col)
	var sombre := Color(Couleurs.UI.panel, 0.9)
	for i in range(4):
		var x := -0.3 + i * 0.2
		_poly(ci, r, [[x - 0.07, 0.1], [x, -0.12], [x + 0.07, 0.1]], sombre)

static func _cri(ci: CanvasItem, r: float, col: Color) -> void:
	_poly(ci, r, [[-0.5, -0.2], [-0.05, -0.05], [-0.5, 0.2]], col)
	for i in range(3):
		ci.draw_arc(Vector2(-0.15 * r, 0.0), r * (0.28 + i * 0.16), -0.7, 0.7, 12, col, r * 0.08, true)

static func _totem(ci: CanvasItem, r: float, col: Color) -> void:
	_poly(ci, r, [[0.0, -0.55], [0.2, -0.15], [0.12, 0.45], [-0.12, 0.45], [-0.2, -0.15]], col)
	_ellipse(ci, Vector2(0.0, 0.45 * r), Vector2(0.5, 0.14) * r, 0.0, col, maxf(1.0, r * 0.05))

# ---------------------------------------------------------------- Supers

static func _sentence(ci: CanvasItem, r: float, col: Color) -> void:
	_rect(ci, r, -0.05, -0.55, 0.1, 0.5, col)
	var pts := PackedVector2Array([Vector2(-0.4, -0.1) * r, Vector2(0.4, -0.1) * r])
	_courbe(pts, Vector2(0.45, 0.35) * r, Vector2(0.0, 0.5) * r)
	_courbe(pts, Vector2(-0.45, 0.35) * r, Vector2(-0.4, -0.1) * r)
	pts.remove_at(pts.size() - 1)
	ci.draw_colored_polygon(pts, col)

static func _nuee(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for p in [[-0.3, -0.2], [0.0, 0.05], [0.3, -0.2], [-0.15, 0.35], [0.15, 0.35]]:
		ci.draw_set_transform(c + Vector2(p[0], p[1]) * r, PI / 2.0)
		_rect(ci, r, -0.25, -0.03, 0.35, 0.06, col)
		_poly(ci, r, [[0.18, 0.0], [0.08, -0.08], [0.08, 0.08]], col)
