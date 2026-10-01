extends "res://jeu/monde/calque.gd"
## Tout ce qui vole, au-dessus des créatures : projectiles ennemis (flèches, orbes des Gardiens),
## Lance du héros, tirs des kits (traits, carreaux, épines, crochet, Nuée) et objets lancés en
## cloche (pot, bombe). Tirs du héros : froids (cyan, blanc). Tirs ennemis : chauds, cernés de
## sombre, à cœur clair, pour se lire sur n'importe quel fond.

const GROSSISSEMENT_ENNEMI := 1.3 # échelle VISUELLE (la hitbox de la simulation ne change pas)
const HAUTEUR_CLOCHE := 70.0 # u : hauteur dessinée d'un objet lancé
const ACIER := Color("#7a8c96")
## Tirs des kits : couleur, longueur de traînée, épaisseur, taille de pointe, rayon de halo.
const STYLES := {
	"arrow": {"couleur": Color("#9ff4ff"), "long": 22.0, "epais": 2.5, "pointe": 7.0, "halo": 16.0},
	"bolt": {"couleur": Color("#9ff4ff"), "long": 16.0, "epais": 4.0, "pointe": 8.0, "halo": 20.0},
	"thorn": {"couleur": Color("#2fc7ff"), "long": 12.0, "epais": 3.0, "pointe": 6.0, "halo": 14.0},
	"hook": {"couleur": Color("#cfe9f5"), "long": 6.0, "epais": 4.0, "pointe": 10.0, "halo": 18.0},
	"star": {"couleur": Color("#e8fbff"), "long": 20.0, "epais": 2.0, "pointe": 6.0, "halo": 18.0},
}

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
	for pr in g.projectiles:
		if D6Js.truthy(pr.get("dead")):
			continue
		var p: Vector2 = partie.position_dessin(pr)
		var angle := Vector2(pr.vx, pr.vy).angle()
		if pr.get("owner") == "player":
			_lance(p, angle)
		elif pr.get("kind") == "bossOrb":
			_orbe(p, pr.r * GROSSISSEMENT_ENNEMI)
		else:
			_fleche(p, angle)
	draw_set_transform(Vector2.ZERO)

## Tir d'un kit du héros : traînée froide et pointe blanche ; le crochet tire sa chaîne.
func _tir_de_kit(s: Dictionary, heros: Vector2) -> void:
	var p: Vector2 = partie.position_dessin(s)
	var style: Dictionary = STYLES.get(s.get("kind"), STYLES.arrow)
	var lourd := 1.4 if D6Js.truthy(s.get("heavy")) else 1.0
	var long: float = style.long * (1.3 if lourd > 1.0 else 1.0)
	draw_set_transform(Vector2.ZERO)
	if s.get("kind") == "hook":
		Trace.ligne_pointillee(self, heros, p, ACIER, 3.0, 7.0, 5.0)
	Trace.halo(self, p, style.halo * lourd, style.couleur, 0.55)
	draw_set_transform(p, Vector2(s.vx, s.vy).angle())
	draw_line(Vector2(-long, 0), Vector2.ZERO, Trace.voile(style.couleur, 0.35), style.epais * lourd + 3.0, true)
	draw_line(Vector2(-long, 0), Vector2.ZERO, style.couleur, style.epais * lourd, true)
	var t: float = style.pointe
	Trace.forme(self, PackedVector2Array([Vector2(t, 0), Vector2(-t * 0.4, -t * 0.6), Vector2(-t * 0.4, t * 0.6)]), PAL.hero, Trace.voile(PAL.heroCape, 0.9), 1.0)

## Pot ou bombe en vol : l'objet monte au-dessus de son ombre.
func _objet_lance(z: Dictionary) -> void:
	draw_set_transform(Vector2.ZERO)
	var sol := Vector2(z.x, z.y)
	var p := sol - Vector2(0, float(z.lift) * HAUTEUR_CLOCHE)
	draw_colored_polygon(Trace.ellipse(sol + Vector2(0, -1.6), 8.4, 4.0), PAL.shadow)
	Trace.halo(self, p, 26.0, PAL.lance, 0.5)
	Trace.disque(self, p, 9.0, Color("#2a6f86") if z.kind == "pot" else Color("#1d2a33"), PAL.lance, 2.0)
	draw_circle(p + Vector2(-3, -3), 2.5, Color(1, 1, 1, 0.5), true, -1.0, true)

## Lance du héros : fer de lance cyan à cœur blanc.
func _lance(p: Vector2, angle: float) -> void:
	draw_set_transform(Vector2.ZERO)
	Trace.halo(self, p, 34.0, PAL.lance, 0.6)
	draw_set_transform(p, angle)
	Trace.forme(self, PackedVector2Array([Vector2(18, 0), Vector2(-30, -5), Vector2(-30, 5)]), PAL.lance, Trace.voile(PAL.heroCape, 0.9), 1.5)
	draw_colored_polygon(PackedVector2Array([Vector2(14, 0), Vector2(-18, -2), Vector2(-18, 2)]), Color(1, 1, 1, 0.85))

## Orbe d'un Gardien : magenta cerné, cœur blanc.
func _orbe(p: Vector2, r: float) -> void:
	draw_set_transform(Vector2.ZERO)
	Trace.halo(self, p, r * 3.0, PAL.bossOrb, 0.55)
	Trace.disque(self, p, r, PAL.bossOrb, Color("#2a0018"), 3.0)
	draw_circle(p, r * 0.45, Color.WHITE, true, -1.0, true)

## Flèche ennemie : fût orange cerné de sombre, filet clair, pointe.
func _fleche(p: Vector2, angle: float) -> void:
	draw_set_transform(Vector2.ZERO)
	Trace.halo(self, p, 20.0, PAL.arrow, 0.5)
	draw_set_transform(p, angle, Vector2(GROSSISSEMENT_ENNEMI, GROSSISSEMENT_ENNEMI))
	draw_line(Vector2(-16, 0), Vector2(10, 0), PAL.enemyOutline, 6.0, true)
	draw_line(Vector2(-16, 0), Vector2(10, 0), PAL.arrow, 3.0, true)
	draw_line(Vector2(-16, 0), Vector2(10, 0), Color("#fff4e0"), 1.2, true)
	Trace.forme(self, PackedVector2Array([Vector2(15, 0), Vector2(6, -5.5), Vector2(6, 5.5)]), PAL.arrow, PAL.enemyOutline, 1.5)
