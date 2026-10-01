extends "res://jeu/monde/calque.gd"
## Ce que le héros vient toucher ou ramasser : l'objet d'interaction de la salle (bénédiction,
## butin, marchand, autel, coffre, fontaine) avec son libellé, et les ramassables (or, soin).
## Rien ici ne blesse : aucune de ces formes n'est rouge.

const Icones = preload("res://jeu/monde/icones.gd")
const MARCHAND := Color("#7fe8ff")
const AUTEL := Color("#b98cff")
const COFFRE := Color("#ffb43c")
const FONTAINE := Color("#6dd8ff")

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var it = g.room.get("interact")
	if it is Dictionary and not D6Js.truthy(it.get("used")):
		_objet(it)
	for pk in g.pickups:
		var p: Vector2 = partie.position_dessin(pk)
		if pk.kind == "gold":
			_or(p, pk)
		else:
			_soin(p)

func _objet(it: Dictionary) -> void:
	var p := Vector2(it.x, it.y)
	var couleur := Color.WHITE
	var libelle := ""
	match it.kind:
		"boon":
			var famille: Dictionary = D6Data.tables().boons.FAMILIES[it.family]
			couleur = Color(famille.color)
			libelle = "Bénédiction · %s" % famille.name
			_benediction(p, couleur)
		"loot":
			couleur = _butin(p, it.item)
			libelle = str(it.item.name)
		"shop":
			couleur = MARCHAND
			libelle = "Marchand des âmes"
			_marchand(p, couleur)
		"event":
			couleur = AUTEL
			libelle = "Autel"
			_autel(p, couleur)
		"treasure":
			couleur = COFFRE
			libelle = "Chambre forte"
			_coffre(p, couleur)
		"rest":
			couleur = FONTAINE
			libelle = "Fontaine du Léthé"
			_fontaine(p, couleur)
	Trace.texte(self, p + Vector2(0, 42.0), libelle, 14, couleur)

func _ombre(p: Vector2, rx: float, ry: float) -> void:
	draw_colored_polygon(Trace.ellipse(p, rx, ry), PAL.shadow)

## Orbe de bénédiction qui flotte, à la couleur de sa famille.
func _benediction(p: Vector2, couleur: Color) -> void:
	var t := temps()
	var q := p + Vector2(0, sin(t * 3.0) * 4.0)
	_ombre(p + Vector2(0, 22.0), 14.0, 5.0)
	Trace.halo(self, q, 70.0, couleur, 0.55)
	Trace.disque(self, q, 15.0, couleur, Trace.CERNE, 2.5)
	draw_circle(q + Vector2(-5, -5), 4.5, Color(1, 1, 1, 0.7), true, -1.0, true)
	draw_circle(q, 22.0 + 3.0 * sin(t * 5.0), Color(1, 1, 1, 0.9), false, 2.0, true)

## Butin au sol : colonne de lumière façon Diablo (plus haute pour les raretés élevées) et glyphe.
func _butin(p: Vector2, item: Dictionary) -> Color:
	var t := temps()
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	var rang := 0
	for i in raretes.size():
		if raretes[i].id == item.rarity:
			rang = i
	var couleur := Color(raretes[rang].color)
	var h := 60.0 + float(rang) * 50.0
	var a := 0.4 + 0.1 * sin(t * 4.0)
	Trace.degrade_vertical(self, Rect2(p.x - 10.0, p.y - h, 20.0, h), Trace.voile(couleur, 0.0), Trace.voile(couleur, a))
	Trace.degrade_vertical(self, Rect2(p.x - 3.0, p.y - h * 0.8, 6.0, h * 0.8), Color(1, 1, 1, 0.0), Color(1, 1, 1, a * 0.6))
	_ombre(p + Vector2(0, 16.0), 16.0, 5.0)
	Trace.halo(self, p, 40.0, couleur, 0.5)
	Icones.objet(self, str(item.slot), p + Vector2(0, sin(t * 3.0) * 2.0), couleur)
	return couleur

## Marchand des âmes : étal de bois, silhouette encapuchonnée aux yeux froids.
func _marchand(p: Vector2, couleur: Color) -> void:
	_ombre(p + Vector2(4, 22.0), 52.0, 9.0)
	Trace.halo(self, p + Vector2(0, -20.0), 50.0, couleur, 0.25)
	var capuche := PackedVector2Array([p + Vector2(-20, -6), p + Vector2(-15, -36), p + Vector2(0, -50), p + Vector2(15, -36), p + Vector2(20, -6)])
	Trace.forme(self, capuche, Color("#241a2c"), Trace.CERNE, 4.5)
	Trace.contour(self, capuche, Color("#57466a"), 1.5)
	draw_colored_polygon(Trace.ellipse(p + Vector2(0, -30.0), 10.0, 9.0), Color("#0b070e"))
	var clin := 0.0 if fmod(temps() + 1.0, 4.0) < 0.12 else 1.0
	for s in [-1.0, 1.0]:
		draw_circle(p + Vector2(s * 5.5, -32.0), 2.2 * clin + 0.4, couleur, true, -1.0, true)
	var etal := Rect2(p.x - 46.0, p.y - 6.0, 92.0, 26.0)
	draw_rect(etal, Color("#3a2430"))
	draw_rect(etal, Trace.CERNE, false, 2.0)
	var plateau := Rect2(p.x - 50.0, p.y - 12.0, 100.0, 8.0)
	draw_rect(plateau, Color("#5a3a44"))
	draw_rect(plateau, Trace.CERNE, false, 2.0)
	for i in 3:
		Trace.disque(self, p + Vector2(-26.0 + 26.0 * float(i), -17.0), 4.0, couleur.lerp(Color.WHITE, 0.3 * float(i)), Trace.CERNE, 1.5)

## Autel : dalle de pierre gravée, flamme violette qui respire.
func _autel(p: Vector2, couleur: Color) -> void:
	var t := temps()
	_ombre(p + Vector2(4, 16.0), 36.0, 8.0)
	Trace.halo(self, p + Vector2(0, -10.0), 60.0, couleur, 0.35 + 0.15 * sin(t * 3.0))
	var dalle := Rect2(p.x - 30.0, p.y - 14.0, 60.0, 28.0)
	draw_rect(dalle, Color("#2e2433"))
	draw_rect(Rect2(dalle.position, Vector2(60.0, 9.0)), Color("#3d3046"))
	draw_rect(dalle, Trace.CERNE, false, 4.5)
	draw_rect(dalle, couleur, false, 2.0)
	Icones.recompense(self, "event", p + Vector2(0, -24.0 + sin(t * 3.0) * 2.0), 9.0, couleur)

## Coffre scellé de la chambre forte : caisse, couvercle bombé, ferrures et sceau qui pulse.
func _coffre(p: Vector2, couleur: Color) -> void:
	var t := temps()
	Trace.halo(self, p + Vector2(0, -6.0), 70.0, couleur, 0.3 + 0.1 * sin(t * 2.5))
	_ombre(p + Vector2(4, 19.0), 38.0, 7.0)
	var couvercle := PackedVector2Array([p + Vector2(-32, -8)])
	for i in range(1, 10):
		var k := float(i) / 10.0
		couvercle.append(p + Vector2(lerpf(-32.0, 32.0, k), -8.0 - 52.0 * k * (1.0 - k)))
	couvercle.append(p + Vector2(32, -8))
	Trace.forme(self, couvercle, Color("#5e3620"), Trace.CERNE, 5.5)
	var caisse := Rect2(p.x - 32.0, p.y - 8.0, 64.0, 26.0)
	draw_rect(caisse, Color("#4a2a1a"))
	draw_rect(caisse, Trace.CERNE, false, 5.5)
	Trace.contour(self, couvercle, couleur, 2.5)
	draw_rect(caisse, couleur, false, 2.5)
	draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 12.0, 14.0), couleur)
	draw_rect(Rect2(p.x - 2.0, p.y - 8.0, 4.0, 6.0), Trace.voile(Color("#fff4c0"), 0.6 + 0.4 * sin(t * 4.0)))

## Fontaine du repos : vasque de pierre, eau claire qui ondule (jamais rouge : rien ne blesse).
func _fontaine(p: Vector2, couleur: Color) -> void:
	var t := temps()
	Trace.halo(self, p + Vector2(0, -4.0), 80.0, couleur, 0.3 + 0.1 * sin(t * 2.0))
	_ombre(p + Vector2(4, 16.0), 40.0, 12.0)
	Trace.forme(self, Trace.ellipse(p + Vector2(0, 4.0), 38.0, 18.0), Color("#3a3440"), Trace.CERNE, 2.5)
	draw_colored_polygon(Trace.ellipse(p + Vector2(0, 2.0), 30.0, 12.0), Trace.voile(couleur, 0.75))
	for i in 2:
		var k := fmod(t * 0.8 + float(i) * 0.5, 1.0)
		Trace.contour(self, Trace.ellipse(p + Vector2(0, 2.0), 6.0 + 22.0 * k, 2.0 + 9.0 * k), Trace.voile(Color("#e8fbff"), 1.0 - k), 1.5)
	var colonne := Rect2(p.x - 5.0, p.y - 26.0, 10.0, 26.0)
	draw_rect(colonne, Color("#5a5262"))
	draw_rect(colonne, Trace.CERNE, false, 2.0)
	Trace.disque(self, p + Vector2(0, -28.0), 5.0 + sin(t * 5.0), couleur, Trace.CERNE, 1.5)

## Pièce d'or : losange cerné, éclat bref de temps en temps.
func _or(p: Vector2, pk: Dictionary) -> void:
	var losange := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)])
	Trace.forme(self, losange, PAL.gold, Color("#5a3c00"), 1.5)
	draw_line(p + Vector2(-3, -0.5), p + Vector2(-0.5, -3), Color(1, 1, 1, 0.8), 1.5, true)
	if fmod(temps() * 4.0 + float(pk.get("id", 0.0)), 3.0) < 0.2:
		Trace.halo(self, p, 16.0, PAL.gold, 0.7)

## Orbe de soin : croix verte dans son halo.
func _soin(p: Vector2) -> void:
	Trace.halo(self, p, 26.0, PAL.heal, 0.5)
	var croix := PackedVector2Array([
		p + Vector2(-3, -9), p + Vector2(3, -9), p + Vector2(3, -3), p + Vector2(9, -3), p + Vector2(9, 3), p + Vector2(3, 3),
		p + Vector2(3, 9), p + Vector2(-3, 9), p + Vector2(-3, 3), p + Vector2(-9, 3), p + Vector2(-9, -3), p + Vector2(-3, -3),
	])
	Trace.forme(self, croix, PAL.heal, Trace.CERNE, 2.0)
