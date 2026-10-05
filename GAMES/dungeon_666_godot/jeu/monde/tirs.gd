extends "res://jeu/monde/calque.gd"
## Tout ce qui vole, au-dessus des créatures : projectiles ennemis (flèches, orbes des Gardiens),
## Lance du héros, tirs des kits (traits, carreaux, épines, crochet, Nuée) et objets lancés en
## cloche (pot, bombe).
## Lecture immédiate : un tir ENNEMI est chaud (orange, magenta), cerné de sombre, à cœur clair ;
## un tir du HÉROS est froid (cyan, blanc), sans cerne. Chacun a une tête lumineuse et une
## traînée effilée dans son sillage, dessinées en mélange additif derrière le corps du tir.
##
## Coût : les corps sont faits de primitives (triangles, quadrilatères) et de pastilles
## texturées, les lumières sont tracées en deux passes (traînées, puis halos) : une salve de
## vingt flèches ou une couronne d'orbes part en quelques appels de dessin.

const GROSSISSEMENT_ENNEMI := 1.3 # échelle VISUELLE (la hitbox de la simulation ne change pas)
const HAUTEUR_CLOCHE := 70.0 # u : hauteur dessinée d'un objet lancé
const SILLAGE := 0.11 # s : la traînée couvre ce que le tir parcourt en ce temps
const ACIER := Color("#7a8c96")
const BRAISE := Color("#ff4a1a")
const CERNE_ORBE := Color("#2a0018")
const FUT_CLAIR := Color("#fff4e0")
## Tirs des kits : couleur, longueur du corps, épaisseur, taille de pointe, rayon de halo.
const STYLES := {
	"arrow": {"couleur": Color("#9ff4ff"), "long": 22.0, "epais": 2.5, "pointe": 7.0, "halo": 18.0},
	"bolt": {"couleur": Color("#9ff4ff"), "long": 16.0, "epais": 4.0, "pointe": 8.0, "halo": 22.0},
	"thorn": {"couleur": Color("#2fc7ff"), "long": 12.0, "epais": 3.0, "pointe": 6.0, "halo": 16.0},
	"hook": {"couleur": Color("#cfe9f5"), "long": 6.0, "epais": 4.0, "pointe": 10.0, "halo": 20.0},
	"star": {"couleur": Color("#e8fbff"), "long": 20.0, "epais": 2.0, "pointe": 6.0, "halo": 20.0},
	# Compétences neuves (étape 4) : le Stigmate est un fer court et gros, la marque de proie un trait
	# fin, le renvoi de la parade un éclat blanc, le Trait de Nemrod un long trait épais.
	"stigmate": {"couleur": Color("#7fe0ff"), "long": 10.0, "epais": 5.0, "pointe": 10.0, "halo": 26.0},
	"marque": {"couleur": Color("#bff8ff"), "long": 26.0, "epais": 2.0, "pointe": 5.0, "halo": 16.0},
	"renvoi": {"couleur": Color("#ffffff"), "long": 18.0, "epais": 3.0, "pointe": 7.0, "halo": 22.0},
	"trait": {"couleur": Color("#e8fbff"), "long": 46.0, "epais": 4.5, "pointe": 12.0, "halo": 34.0},
	"hache": {"couleur": Color("#cfe9f5"), "long": 0.0, "epais": 6.0, "pointe": 0.0, "halo": 30.0},
}
const TOURS_HACHE := 3.2 # tours par seconde de la Hache du supplice en vol

func _init() -> void:
	lumieres_derriere = true

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var reserve = g.room.get("kitFx")
	if reserve is Dictionary:
		var heros: Vector2 = partie.position_dessin(g.player, true)
		for s in reserve.shots:
			if not D6Js.truthy(s.get("dead")):
				_tir_de_kit(s, heros)
		for z in reserve.zones:
			if not D6Js.truthy(z.get("dead")) and float(z.get("lift", 0.0)) > 0.0:
				_objet_lance(z)
	# Flèches et lances d'abord (primitives), orbes ensuite (pastilles) : deux lots.
	for pr in g.projectiles:
		if D6Js.truthy(pr.get("dead")) or pr.get("kind") == "bossOrb":
			continue
		if pr.get("owner") == "player":
			_lance(partie.position_dessin(pr), Vector2(pr.vx, pr.vy).angle())
		else:
			_fleche(partie.position_dessin(pr), Vector2(pr.vx, pr.vy).angle())
	draw_set_transform(Vector2.ZERO)
	for pr in g.projectiles:
		if not D6Js.truthy(pr.get("dead")) and pr.get("kind") == "bossOrb" and pr.get("owner") != "player":
			Trace.pastille(self, partie.position_dessin(pr), pr.r * GROSSISSEMENT_ENNEMI * 1.12, Color.WHITE, PAL.bossOrb, CERNE_ORBE)

func _triangle(a: Vector2, b: Vector2, c: Vector2, couleur: Color) -> void:
	Trace.triangle(self, a, b, c, couleur, couleur, couleur)

## Tir d'un kit du héros : trait froid et pointe blanche ; le crochet tire sa chaîne.
func _tir_de_kit(s: Dictionary, heros: Vector2) -> void:
	var p: Vector2 = partie.position_dessin(s)
	if s.get("kind") == "hache":
		_hache(s, p)
		return
	var style: Dictionary = STYLES.get(s.get("kind"), STYLES.arrow)
	var lourd := 1.4 if D6Js.truthy(s.get("heavy")) else 1.0
	var long: float = style.long * (1.3 if lourd > 1.0 else 1.0)
	draw_set_transform(Vector2.ZERO)
	if s.get("kind") == "hook":
		Trace.ligne_pointillee(self, heros, p, ACIER, 3.0, 7.0, 5.0)
	draw_set_transform(p, Vector2(s.vx, s.vy).angle())
	draw_line(Vector2(-long, 0), Vector2.ZERO, style.couleur, style.epais * lourd, true)
	draw_line(Vector2(-long * 0.7, 0), Vector2.ZERO, Color.WHITE, style.epais * lourd * 0.4, true)
	var t: float = style.pointe
	_triangle(Vector2(t + 1.5, 0), Vector2(-t * 0.4 - 1.0, -t * 0.6 - 1.5), Vector2(-t * 0.4 - 1.0, t * 0.6 + 1.5), Trace.voile(PAL.heroCape, 0.9))
	_triangle(Vector2(t, 0), Vector2(-t * 0.4, -t * 0.6), Vector2(-t * 0.4, t * 0.6), PAL.hero)

## Hache du supplice : elle TOURNE sur elle-même (manche, fer en croissant, tranchant clair), au-dessus
## de son ombre ; quand elle tournoie sur place (amélioration), le cercle qu'elle fauche est dit.
func _hache(s: Dictionary, p: Vector2) -> void:
	draw_set_transform(Vector2.ZERO)
	Trace.halo_ovale(self, p + Vector2(0, 12.0), 15.0, 7.0, Color.BLACK, 0.7)
	if s.get("phase") == "spin":
		Trace.cercle_pointille(self, p, s.spinRadius, Trace.voile(PAL.lance, 0.7), 2.0, 9.0, 7.0, temps() * 60.0)
	draw_set_transform(p, temps() * TAU * TOURS_HACHE)
	draw_line(Vector2(-16, 0), Vector2(12, 0), Trace.voile(PAL.heroCape, 0.9), 5.0, true)
	draw_line(Vector2(-15, 0), Vector2(11, 0), Color("#cfe9f5"), 2.5, true)
	var fer := PackedVector2Array([Vector2(4, -3), Vector2(8, -17), Vector2(19, -12), Vector2(22, 0), Vector2(19, 12), Vector2(8, 17), Vector2(4, 3)])
	Trace.forme(self, fer, PAL.lance, Trace.voile(PAL.heroCape, 0.95), 2.0)
	draw_polyline(PackedVector2Array([Vector2(19, -12), Vector2(22, 0), Vector2(19, 12)]), Color.WHITE, 2.0, true)

## Pot ou bombe en vol : l'objet monte au-dessus de son ombre.
func _objet_lance(z: Dictionary) -> void:
	draw_set_transform(Vector2.ZERO)
	var sol := Vector2(z.x, z.y)
	var p := sol - Vector2(0, float(z.lift) * HAUTEUR_CLOCHE)
	Trace.halo_ovale(self, sol + Vector2(0, -1.6), 13.0, 6.5, Color.BLACK, 0.8)
	Trace.pastille(self, p, 10.5, Color("#2a6f86") if z.kind == "pot" else Color("#1d2a33"), Color("#2a6f86") if z.kind == "pot" else Color("#1d2a33"), PAL.lance)
	Trace.halo(self, p + Vector2(-3, -3), 4.0, Color.WHITE, 0.6)

## Lance du héros : fer de lance cyan à cœur blanc.
func _lance(p: Vector2, angle: float) -> void:
	draw_set_transform(p, angle)
	_triangle(Vector2(20, 0), Vector2(-31, -6.5), Vector2(-31, 6.5), Trace.voile(PAL.heroCape, 0.9))
	_triangle(Vector2(18, 0), Vector2(-30, -5), Vector2(-30, 5), PAL.lance)
	Trace.triangle(self, Vector2(14, 0), Vector2(-18, -2), Vector2(-18, 2), Color.WHITE, Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.7))

## Flèche ennemie : fût orange cerné de sombre, filet clair, pointe.
func _fleche(p: Vector2, angle: float) -> void:
	draw_set_transform(p, angle, Vector2(GROSSISSEMENT_ENNEMI, GROSSISSEMENT_ENNEMI))
	draw_line(Vector2(-17.5, 0), Vector2(10, 0), PAL.enemyOutline, 6.0, true)
	draw_line(Vector2(-16, 0), Vector2(10, 0), PAL.arrow, 3.0, true)
	draw_line(Vector2(-14, 0), Vector2(10, 0), FUT_CLAIR, 1.2, true)
	_triangle(Vector2(17.5, 0), Vector2(5, -7.5), Vector2(5, 7.5), PAL.enemyOutline)
	_triangle(Vector2(15, 0), Vector2(6.5, -5), Vector2(6.5, 5), PAL.arrow)

## Les lumières (mélange additif, derrière les corps) : la traînée et la tête de chaque tir.
## Deux passes : toutes les traînées (primitives), puis tous les halos (une texture).
func _dessiner_lumieres(c: CanvasItem) -> void:
	var tirs := _tirs_lumineux(etat())
	for t in tirs:
		if t.v != Vector2.ZERO:
			var fin: Vector2 = t.p - t.v.normalized() * clampf(t.v.length() * SILLAGE, 28.0, 96.0)
			Trace.trainee(c, t.p, fin, t.largeur, t.queue, 0.7)
			Trace.trainee(c, t.p, t.p.lerp(fin, 0.55), t.largeur * 0.5, t.tete, 0.9)
	for t in tirs:
		Trace.halo(c, t.p, t.halo, t.tete, 0.6)

## Ce qui brille : [{p, v: vitesse (ZERO = pas de traînée), tete, queue: couleurs, largeur, halo}].
func _tirs_lumineux(g: Dictionary) -> Array:
	var tirs: Array = []
	var reserve = g.room.get("kitFx")
	if reserve is Dictionary:
		for s in reserve.shots:
			if D6Js.truthy(s.get("dead")):
				continue
			var style: Dictionary = STYLES.get(s.get("kind"), STYLES.arrow)
			var lourd := 1.4 if D6Js.truthy(s.get("heavy")) else 1.0
			tirs.append({"p": partie.position_dessin(s), "v": Vector2(s.vx, s.vy), "tete": style.couleur, "queue": PAL.heroCape, "largeur": (style.epais + 5.0) * lourd, "halo": style.halo * lourd})
		for z in reserve.zones:
			if not D6Js.truthy(z.get("dead")) and float(z.get("lift", 0.0)) > 0.0:
				tirs.append({"p": Vector2(z.x, z.y) - Vector2(0, float(z.lift) * HAUTEUR_CLOCHE), "v": Vector2.ZERO, "tete": PAL.lance, "queue": PAL.lance, "largeur": 0.0, "halo": 28.0})
	for pr in g.projectiles:
		if D6Js.truthy(pr.get("dead")):
			continue
		var tir := {"p": partie.position_dessin(pr), "v": Vector2(pr.vx, pr.vy), "tete": PAL.arrow, "queue": BRAISE, "largeur": 13.0, "halo": 26.0}
		if pr.get("owner") == "player":
			tir.merge({"tete": PAL.lance, "queue": PAL.heroCape, "largeur": 12.0, "halo": 36.0}, true)
		elif pr.get("kind") == "bossOrb":
			tir.merge({"tete": PAL.bossOrb, "queue": PAL.bossOrb, "largeur": pr.r * 2.2, "halo": pr.r * 3.4}, true)
		tirs.append(tir)
	return tirs
