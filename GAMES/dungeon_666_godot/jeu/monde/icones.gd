extends RefCounted
## Pictogrammes du monde, dessinés en formes pleines cernées de sombre : l'icône de récompense
## d'une porte, le glyphe d'un objet de butin. Portage de drawRewardIcon et drawItemGlyph
## (GAMES/dungeon_666/src/render/render.mjs).
##   const Icones = preload("res://jeu/monde/icones.gd")   puis   Icones.recompense(self, "boon", p, 13.0, c)

const Trace = preload("res://jeu/monde/trace.gd")
const CERNE := Color(0, 0, 0, 0.75)

## Icône de la récompense `nom` (clé de porte : boon, loot, gold, heal, boss, town…), de rayon r.
static func recompense(c: CanvasItem, nom: String, p: Vector2, r: float, couleur: Color) -> void:
	match nom:
		"boon":
			Trace.disque(c, p, r, couleur, CERNE)
			c.draw_circle(p + Vector2(-r, -r) * 0.3, r * 0.28, Color(1, 1, 1, 0.55), true, -1.0, true)
		"loot", "elite":
			Trace.forme(c, PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), couleur, CERNE)
		"gold":
			Trace.forme(c, Trace.ellipse(p, r, r * 0.8), couleur, CERNE)
			c.draw_arc(p, r * 0.5, -2.6, -0.6, 8, Color(1, 1, 1, 0.5), 1.5, true)
		"heal":
			Trace.forme(c, _croix(p, r, r * 0.35), couleur, CERNE)
		"boss":
			_gardien(c, p, r, couleur)
		"town":
			c.draw_circle(p, r * 0.78, CERNE, false, r * 0.45 + 3.0, true)
			c.draw_circle(p, r * 0.78, couleur, false, r * 0.45, true)
		"treasure":
			_coffre(c, p, r, couleur)
		"rest":
			Trace.forme(c, _goutte(p, r), couleur, CERNE)
		"shop":
			_bourse(c, p, r, couleur)
		"event":
			_flamme(c, p, r, couleur)
		_:
			Trace.forme(c, PackedVector2Array([p + Vector2(-r, -r) * 0.8, p + Vector2(r, -r) * 0.8, p + Vector2(r, r) * 0.8, p + Vector2(-r, r) * 0.8]), couleur, CERNE)

static func _croix(p: Vector2, r: float, b: float) -> PackedVector2Array:
	return PackedVector2Array([
		p + Vector2(-b, -r), p + Vector2(b, -r), p + Vector2(b, -b), p + Vector2(r, -b),
		p + Vector2(r, b), p + Vector2(b, b), p + Vector2(b, r), p + Vector2(-b, r),
		p + Vector2(-b, b), p + Vector2(-r, b), p + Vector2(-r, -b), p + Vector2(-b, -b),
	])

## Tête cornue du Gardien.
static func _gardien(c: CanvasItem, p: Vector2, r: float, couleur: Color) -> void:
	for s in [-1.0, 1.0]:
		var corne := PackedVector2Array([p + Vector2(s * r, -r * 0.4), p + Vector2(s * r * 0.6, -r * 1.4), p + Vector2(s * r * 0.2, -r * 0.6)])
		Trace.forme(c, corne, couleur, CERNE)
	Trace.disque(c, p, r, couleur, CERNE)

## Coffre : caisse et couvercle bombé.
static func _coffre(c: CanvasItem, p: Vector2, r: float, couleur: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(-r, r * 0.8), p + Vector2(-r, -r * 0.2)])
	for i in range(1, 8):
		var k := float(i) / 8.0
		pts.append(p + Vector2(lerpf(-r, r, k), -r * 0.2 - r * 0.55 * 4.0 * k * (1.0 - k)))
	pts.append(p + Vector2(r, -r * 0.2))
	pts.append(p + Vector2(r, r * 0.8))
	Trace.forme(c, pts, couleur, CERNE)
	c.draw_line(p + Vector2(-r, -r * 0.2), p + Vector2(r, -r * 0.2), CERNE, 1.5, true)

## Goutte d'eau (fontaine) : pointe en haut, ventre rond.
static func _goutte(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array([p + Vector2(0, -r * 1.2)])
	var ventre := p + Vector2(0, r * 0.2)
	pts.append_array(Trace.arc(ventre, r * 0.75, -0.5, PI + 0.5, 14))
	return pts

## Bourse du marchand : sac rond et col noué.
static func _bourse(c: CanvasItem, p: Vector2, r: float, couleur: Color) -> void:
	var col := PackedVector2Array([p + Vector2(-r * 0.55, -r * 1.1), p + Vector2(r * 0.55, -r * 1.1), p + Vector2(r * 0.25, -r * 0.4), p + Vector2(-r * 0.25, -r * 0.4)])
	Trace.forme(c, col, couleur, CERNE)
	Trace.disque(c, p + Vector2(0, r * 0.2), r * 0.85, couleur, CERNE)
	c.draw_line(p + Vector2(-r * 0.4, -r * 0.5), p + Vector2(r * 0.4, -r * 0.5), CERNE, 1.5, true)

## Flamme de l'autel.
static func _flamme(c: CanvasItem, p: Vector2, r: float, couleur: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r * 1.3), p + Vector2(r * 0.45, -r * 0.35)])
	pts.append_array(Trace.arc(p + Vector2(0, r * 0.25), r * 0.75, -0.6, PI + 0.6, 12))
	pts.append(p + Vector2(-r * 0.45, -r * 0.35))
	Trace.forme(c, pts, couleur, CERNE)
	c.draw_circle(p + Vector2(0, r * 0.35), r * 0.3, Color(1, 1, 1, 0.6), true, -1.0, true)

## Glyphe d'un objet de butin selon son emplacement : arme, armure, sinon anneau.
static func objet(c: CanvasItem, emplacement: String, p: Vector2, couleur: Color) -> void:
	var cerne := Color("#120a0e")
	if emplacement == "arme":
		c.draw_set_transform(p, -PI / 4.0)
		Trace.forme(c, PackedVector2Array([Vector2(-3, 8), Vector2(-3, -14), Vector2(0, -20), Vector2(3, -14), Vector2(3, 8)]), couleur, cerne)
		Trace.forme(c, PackedVector2Array([Vector2(-9, 6), Vector2(9, 6), Vector2(9, 10), Vector2(-9, 10)]), couleur, cerne)
		Trace.forme(c, PackedVector2Array([Vector2(-2, 10), Vector2(2, 10), Vector2(2, 18), Vector2(-2, 18)]), couleur, cerne)
		c.draw_set_transform(Vector2.ZERO)
	elif emplacement == "armure":
		Trace.forme(c, PackedVector2Array([p + Vector2(-14, -12), p + Vector2(-5, -12), p + Vector2(0, -8), p + Vector2(5, -12), p + Vector2(14, -12), p + Vector2(10, 14), p + Vector2(-10, 14)]), couleur, cerne)
	else:
		c.draw_circle(p, 7.0, cerne, false, 9.0, true)
		c.draw_circle(p, 7.0, couleur, false, 5.5, true)
