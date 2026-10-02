extends "res://jeu/monde/calque.gd"
## Ce que le héros vient toucher ou ramasser : l'objet d'interaction de la salle (bénédiction,
## butin, marchand, autel, coffre, fontaine) avec son libellé, et les ramassables (or, soin).
## Chaque objet a une PRÉSENCE : un cercle de runes qui tourne au sol (« viens ici »), un halo
## qui respire et des étincelles qui montent (calque additif), un flottement.
## Rien ici ne blesse : aucune de ces formes n'est rouge.
##
## PROFONDEUR. Ce calque est au SOL, sous tout ce qui est debout : il garde les runes, les halos
## et les ramassables (une pièce reste sous les pieds de qui passe dessus). Ce qui se DRESSE passe
## par des relais rangés dans le groupe trié des créatures et des piliers (Entites/Debout) :
##   l'objet d'interaction   son corps, son libellé, sa colonne de lumière et ses étincelles, au
##                           rang de son pied : un pilier plus au nord ne le recouvre plus
##   un ramassable masqué    tombé juste au nord d'un pilier, il serait caché par le dessus du
##                           pilier : il est repeint au rang de ce pilier, juste devant lui. Il
##                           doit se LIRE (le héros le cherche) ; l'exactitude du recouvrement
##                           compte moins qu'une pièce qu'on ne voit pas
## Coût : tous les ramassables au sol partent en un appel de dessin (jeu/theme/triangles.gd), un de plus par
## pilier qui en masque.

const Icones = preload("res://jeu/monde/icones.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const Piliers = preload("res://jeu/monde/piliers.gd")
const MARCHAND := Color("#7fe8ff")
const AUTEL := Color("#b98cff")
const COFFRE := Color("#ffb43c")
const FONTAINE := Color("#6dd8ff")
const LIBELLES := {"shop": "Marchand des âmes", "event": "Autel", "treasure": "Chambre forte", "rest": "Fontaine du Léthé"}
const TEINTES := {"shop": MARCHAND, "event": AUTEL, "treasure": COFFRE, "rest": FONTAINE}
const ETINCELLES := 7
const RUNES := 46.0 # u : rayon du cercle de runes
const EMPRISE := 10.0 # u : demi-largeur dessinée d'un ramassable
const DEVANT := 0.5 # u : un ramassable masqué passe juste devant le pied de son pilier
const CERNE_OR := Color("#5a3c00")

static var _losange := PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)])
static var _croix := PackedVector2Array([
	Vector2(-3, -9), Vector2(3, -9), Vector2(3, -3), Vector2(9, -3), Vector2(9, 3), Vector2(3, 3),
	Vector2(3, 9), Vector2(-3, 9), Vector2(-3, 3), Vector2(-9, 3), Vector2(-9, -3), Vector2(-3, -3)])

var _lot := Triangles.new()
## Les relais du groupe trié : celui de l'objet d'interaction, ceux des ramassables masqués
## (rang du pilier -> son relais), et ce que chacun peint à cette image.
var _debout: Node2D = null
var _corps: Node2D = null
var _leves := {}
var _au_sol: Array = []
var _masques := {} # rang du pilier -> ses ramassables masqués

func _init() -> void:
	lumieres_derriere = true

func relier(p_monde: Node2D, p_partie: Node) -> void:
	super(p_monde, p_partie)
	if _debout != null:
		return
	_debout = Node2D.new()
	_debout.name = "Objets"
	_debout.y_sort_enabled = true
	var groupe = monde.entites.get("debout") if monde.get("entites") != null else null
	(groupe if groupe is Node2D else self).add_child(_debout)
	_corps = _relais("Objet", _peindre_objet, _eclairer_objet)

## Un relais du groupe trié : un nœud, et ses lumières (additives) derrière lui.
func _relais(nom: String, peindre: Callable, eclairer: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = nom
	var lumieres := Node2D.new()
	lumieres.name = "Lumieres"
	var additif := CanvasItemMaterial.new()
	additif.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	lumieres.material = additif
	lumieres.show_behind_parent = true
	n.add_child(lumieres)
	n.draw.connect(peindre.bind(n))
	lumieres.draw.connect(eclairer.bind(lumieres, n))
	_debout.add_child(n)
	return n

func redessiner() -> void:
	if _debout == null:
		super()
		return
	_ranger()
	super()
	for n in _debout.get_children():
		if n.visible:
			n.queue_redraw()
			n.get_child(0).queue_redraw()

## Une image : l'objet à son rang, chaque ramassable au sol ou devant le pilier qui le masque.
func _ranger() -> void:
	var g = etat()
	var it = _objet_present(g) if g != null else null
	_corps.visible = it != null
	if it != null:
		_corps.position = Vector2(it.x, it.y)
	_au_sol.clear()
	for liste in _masques.values():
		liste.clear()
	if g != null:
		var obstacles: Array = g.room.obstacles
		for pk in g.pickups:
			var rang := pilier_masquant(obstacles, partie.position_dessin(pk))
			if rang < 0:
				_au_sol.append(pk)
			else:
				_leve(rang, obstacles[rang]).append(pk)
	for rang in _leves:
		_leves[rang].visible = not _masques[rang].is_empty()

## Les ramassables masqués par le pilier de ce rang (leur relais est créé au besoin, posé devant lui).
func _leve(rang: int, o: Dictionary) -> Array:
	if not _leves.has(rang):
		_leves[rang] = _relais("Leves%d" % rang, _peindre_leves.bind(rang), _eclairer_leves.bind(rang))
		_masques[rang] = []
	_leves[rang].position = Vector2(0.0, o.y1 + DEVANT)
	return _masques[rang]

## Rang du pilier dont le dessus (remonté de sa hauteur) recouvrirait un ramassable posé en `q`,
## ou -1. Un ramassable n'est jamais DANS un pilier : seul celui tombé juste au nord est masqué.
static func pilier_masquant(obstacles: Array, q: Vector2) -> int:
	for i in obstacles.size():
		var o: Dictionary = obstacles[i]
		if q.x > o.x0 - EMPRISE and q.x < o.x1 + EMPRISE and q.y < o.y1 and q.y > o.y0 - Piliers.HAUTEUR - EMPRISE:
			return i
	return -1

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var it = _objet_present(g)
	if it != null:
		_runes(Vector2(it.x, it.y + 10.0), _couleur(it))
	_ramassables(self, _au_sol)

## L'objet d'interaction de la salle s'il attend encore le héros, sinon null.
func _objet_present(g: Dictionary):
	var it = g.room.get("interact")
	if it is Dictionary and not D6Js.truthy(it.get("used")):
		return it
	return null

## Couleur de l'objet : sa famille (bénédiction), sa rareté (butin), sinon son genre.
func _couleur(it: Dictionary) -> Color:
	match it.kind:
		"boon":
			return Color(D6Data.tables().boons.FAMILIES[it.family].color)
		"loot":
			return Color(_rarete(it.item).color)
	return TEINTES.get(it.kind, Color.WHITE)

func _rarete(item: Dictionary) -> Dictionary:
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	for r in raretes:
		if r.id == item.rarity:
			return r
	return raretes[0]

func _rang_de_rarete(item: Dictionary) -> int:
	var raretes: Array = D6Data.tables().loot.ITEM_RARITIES
	for i in raretes.size():
		if raretes[i].id == item.rarity:
			return i
	return 0

## Le corps de l'objet d'interaction, peint sur son relais (origine à son pied).
func _peindre_objet(c: CanvasItem) -> void:
	var g = etat()
	var it = _objet_present(g) if g != null else null
	if it == null:
		return
	var p := Vector2.ZERO
	var couleur := _couleur(it)
	var libelle: String = LIBELLES.get(it.kind, "")
	match it.kind:
		"boon":
			libelle = "Bénédiction · %s" % D6Data.tables().boons.FAMILIES[it.family].name
			_benediction(c, p, couleur)
		"loot":
			libelle = str(it.item.name)
			_butin(c, p, it.item, couleur)
		"shop":
			_marchand(c, p, couleur)
		"event":
			_autel(c, p, couleur)
		"treasure":
			_coffre(c, p, couleur)
		"rest":
			_fontaine(c, p, couleur)
	Trace.texte(c, p + Vector2(0, 50.0), libelle, 15, couleur)

## Cercle de runes au sol, aplati par la vue : deux anneaux pointillés qui tournent à contresens.
func _runes(p: Vector2, couleur: Color) -> void:
	var t := temps()
	draw_set_transform(p, 0.0, Vector2(1.0, 0.52))
	Trace.cercle_pointille(self, Vector2.ZERO, RUNES, Trace.voile(couleur, 0.5 + 0.15 * sin(t * 2.0)), 2.0, 9.0, 7.0, t * 16.0)
	Trace.cercle_pointille(self, Vector2.ZERO, RUNES + 9.0, Trace.voile(couleur, 0.22), 1.5, 3.0, 11.0, -t * 10.0)
	draw_set_transform(Vector2.ZERO)

func _ombre(c: CanvasItem, p: Vector2, rx: float, ry: float) -> void:
	Trace.halo_ovale(c, p, rx * 1.5, ry * 1.6, Color.BLACK, 0.75)

## Orbe de bénédiction qui flotte, à la couleur de sa famille.
func _benediction(c: CanvasItem, p: Vector2, couleur: Color) -> void:
	var t := temps()
	var q := p + Vector2(0, -6.0 + sin(t * 2.6) * 5.0)
	_ombre(c, p + Vector2(0, 22.0), 14.0, 5.0)
	Trace.disque(c, q, 15.0, couleur, Trace.CERNE, 2.5)
	c.draw_circle(q + Vector2(3, 4), 9.0, Trace.voile(couleur.darkened(0.35), 0.5), true, -1.0, true)
	c.draw_circle(q + Vector2(-5, -5), 4.5, Color(1, 1, 1, 0.8), true, -1.0, true)
	c.draw_arc(q, 22.0 + 2.0 * sin(t * 5.0), t * 1.5, t * 1.5 + 4.6, 20, Color(1, 1, 1, 0.9), 2.0, true)

## Butin au sol : glyphe qui flotte au pied de sa colonne de lumière (dessinée en additif).
func _butin(c: CanvasItem, p: Vector2, item: Dictionary, couleur: Color) -> void:
	_ombre(c, p + Vector2(0, 18.0), 16.0, 5.0)
	Icones.objet(c, str(item.slot), p + Vector2(0, -4.0 + sin(temps() * 3.0) * 3.0), couleur)

## Marchand des âmes : étal de bois, silhouette encapuchonnée aux yeux froids, lanterne.
func _marchand(c: CanvasItem, p: Vector2, couleur: Color) -> void:
	_ombre(c, p + Vector2(4, 22.0), 52.0, 9.0)
	var capuche := PackedVector2Array([p + Vector2(-20, -6), p + Vector2(-15, -36), p + Vector2(0, -50), p + Vector2(15, -36), p + Vector2(20, -6)])
	Trace.forme(c, capuche, Color("#241a2c"), Trace.CERNE, 4.5)
	Trace.contour(c, capuche, Color("#57466a"), 1.5)
	c.draw_colored_polygon(Trace.ellipse(p + Vector2(0, -30.0), 10.0, 9.0), Color("#0b070e"))
	var clin := 0.0 if fmod(temps() + 1.0, 4.0) < 0.12 else 1.0
	for s in [-1.0, 1.0]:
		c.draw_circle(p + Vector2(s * 5.5, -32.0), 2.2 * clin + 0.4, couleur, true, -1.0, true)
	var etal := Rect2(p.x - 46.0, p.y - 6.0, 92.0, 26.0)
	Trace.degrade_vertical(c, etal, Color("#4a2e3a"), Color("#2a1822"))
	c.draw_rect(etal, Trace.CERNE, false, 2.0)
	var plateau := Rect2(p.x - 50.0, p.y - 12.0, 100.0, 8.0)
	c.draw_rect(plateau, Color("#6a4650"))
	c.draw_rect(Rect2(plateau.position, Vector2(100.0, 2.0)), Color(1, 0.9, 0.8, 0.25))
	c.draw_rect(plateau, Trace.CERNE, false, 2.0)
	for i in 3:
		Trace.disque(c, p + Vector2(-26.0 + 26.0 * float(i), -17.0), 4.0, couleur.lerp(Color.WHITE, 0.3 * float(i)), Trace.CERNE, 1.5)
	var lanterne := p + Vector2(40.0 + sin(temps() * 1.7) * 1.5, -30.0)
	c.draw_line(Vector2(p.x + 40.0, p.y - 12.0), lanterne, Color("#1a1216"), 2.0)
	Trace.disque(c, lanterne, 5.0, couleur.lerp(Color.WHITE, 0.5), Trace.CERNE, 1.5)

## Autel : dalle de pierre gravée, flamme violette qui respire.
func _autel(c: CanvasItem, p: Vector2, couleur: Color) -> void:
	var t := temps()
	_ombre(c, p + Vector2(4, 16.0), 36.0, 8.0)
	var dalle := Rect2(p.x - 30.0, p.y - 14.0, 60.0, 28.0)
	Trace.degrade_vertical(c, dalle, Color("#3a2e42"), Color("#221a28"))
	c.draw_rect(Rect2(dalle.position, Vector2(60.0, 9.0)), Color("#4a3c56"))
	c.draw_rect(Rect2(dalle.position, Vector2(60.0, 2.0)), Color(1, 0.92, 1.0, 0.22))
	c.draw_rect(dalle, Trace.CERNE, false, 4.5)
	c.draw_rect(dalle, Trace.voile(couleur, 0.75 + 0.25 * sin(t * 3.0)), false, 2.0)
	Icones.recompense(c, "event", p + Vector2(0, -26.0 + sin(t * 3.0) * 2.5), 10.0, couleur)

## Coffre scellé de la chambre forte : caisse, couvercle bombé, ferrures et sceau qui pulse.
func _coffre(c: CanvasItem, p: Vector2, couleur: Color) -> void:
	var t := temps()
	_ombre(c, p + Vector2(4, 19.0), 38.0, 7.0)
	var couvercle := PackedVector2Array([p + Vector2(-32, -8)])
	for i in range(1, 10):
		var k := float(i) / 10.0
		couvercle.append(p + Vector2(lerpf(-32.0, 32.0, k), -8.0 - 52.0 * k * (1.0 - k)))
	couvercle.append(p + Vector2(32, -8))
	Trace.forme(c, couvercle, Color("#6a3e24"), Trace.CERNE, 5.5)
	var caisse := Rect2(p.x - 32.0, p.y - 8.0, 64.0, 26.0)
	Trace.degrade_vertical(c, caisse, Color("#57321e"), Color("#341c10"))
	c.draw_rect(caisse, Trace.CERNE, false, 5.5)
	Trace.contour(c, couvercle, couleur, 2.5)
	c.draw_rect(caisse, couleur, false, 2.5)
	for x in [-20.0, 20.0]:
		c.draw_rect(Rect2(p.x + x - 2.0, p.y - 8.0, 4.0, 26.0), Trace.voile(couleur, 0.7))
	c.draw_rect(Rect2(p.x - 6.0, p.y - 12.0, 12.0, 14.0), couleur)
	c.draw_rect(Rect2(p.x - 2.0, p.y - 8.0, 4.0, 6.0), Trace.voile(Color("#fff4c0"), 0.6 + 0.4 * sin(t * 4.0)))

## Fontaine du repos : vasque de pierre, eau claire qui ondule (jamais rouge : rien ne blesse).
func _fontaine(c: CanvasItem, p: Vector2, couleur: Color) -> void:
	var t := temps()
	_ombre(c, p + Vector2(4, 16.0), 40.0, 12.0)
	Trace.forme(c, Trace.ellipse(p + Vector2(0, 4.0), 38.0, 18.0), Color("#4a4452"), Trace.CERNE, 2.5)
	c.draw_colored_polygon(Trace.ellipse(p + Vector2(0, 2.0), 30.0, 12.0), Trace.voile(couleur, 0.8))
	for i in 2:
		var k := fmod(t * 0.8 + float(i) * 0.5, 1.0)
		Trace.contour(c, Trace.ellipse(p + Vector2(0, 2.0), 6.0 + 22.0 * k, 2.0 + 9.0 * k), Trace.voile(Color("#e8fbff"), 1.0 - k), 1.5)
	var colonne := Rect2(p.x - 5.0, p.y - 26.0, 10.0, 26.0)
	Trace.degrade_horizontal(c, colonne, Color("#7a7284"), Color("#4a4452"))
	c.draw_rect(colonne, Trace.CERNE, false, 2.0)
	Trace.disque(c, p + Vector2(0, -28.0), 5.0 + sin(t * 5.0), couleur.lerp(Color.WHITE, 0.35), Trace.CERNE, 1.5)

## Les ramassables de `liste`, en un lot, sur `c` (le sol, ou le relais d'un pilier).
func _ramassables(c: Node2D, liste: Array) -> void:
	_lot.repere = Transform2D(0.0, -c.position)
	for pk in liste:
		var p: Vector2 = partie.position_dessin(pk)
		if pk.kind == "gold":
			_or(p)
		else:
			_soin(p)
	_lot.tracer(c)

func _peindre_leves(c: Node2D, rang: int) -> void:
	_ramassables(c, _masques[rang])

## Pièce d'or : losange cerné, reflet.
func _or(p: Vector2) -> void:
	var place := Transform2D(0.0, p)
	_lot.polygone(_losange, PAL.gold, place)
	_lot.contour(_losange, CERNE_OR, 1.5, false, place)
	_lot.ligne(p + Vector2(-3, -0.5), p + Vector2(-0.5, -3), Color(1, 1, 1, 0.8), 1.5, false)

## Orbe de soin : croix verte.
func _soin(p: Vector2) -> void:
	var place := Transform2D(0.0, p + Vector2(0, sin(temps() * 3.0 + p.x) * 2.0))
	_lot.polygone(_croix, PAL.heal, place)
	_lot.contour(_croix, Trace.CERNE, 2.0, false, place)

## Les lumières du sol (mélange additif) : halos de l'objet, éclats des ramassables au sol.
func _dessiner_lumieres(c: CanvasItem) -> void:
	var it = _objet_present(etat())
	if it != null:
		var p := Vector2(it.x, it.y)
		var couleur := _couleur(it)
		var souffle := 0.8 + 0.2 * sin(temps() * 2.4)
		Trace.halo_ovale(c, p + Vector2(0, 12.0), 130.0, 76.0, couleur, 0.4 * souffle)
		Trace.halo(c, p + Vector2(0, -10.0), 70.0, couleur, 0.6 * souffle)
	_eclats(c, _au_sol, Vector2.ZERO)

## Les lumières DEBOUT de l'objet (sur son relais) : colonne du butin, étincelles qui montent.
func _eclairer_objet(c: CanvasItem, _relais_objet: Node2D) -> void:
	var g = etat()
	var it = _objet_present(g) if g != null else null
	if it == null:
		return
	var couleur := _couleur(it)
	if it.kind == "loot":
		_colonne(c, Vector2.ZERO, couleur, 70.0 + 50.0 * float(_rang_de_rarete(it.item)), 0.8 + 0.2 * sin(temps() * 2.4))
	_etincelles(c, Vector2.ZERO, couleur, temps())

func _eclairer_leves(c: CanvasItem, relais: Node2D, rang: int) -> void:
	_eclats(c, _masques[rang], relais.position)

## Éclats des ramassables de `liste` ; `origine` : la position du nœud qui les porte.
func _eclats(c: CanvasItem, liste: Array, origine: Vector2) -> void:
	var t := temps()
	for pk in liste:
		var q: Vector2 = partie.position_dessin(pk) - origine
		if pk.kind == "gold":
			var eclat := maxf(0.0, sin(t * 4.0 + float(pk.get("id", 0.0)) * 1.3))
			Trace.halo(c, q, 15.0, PAL.gold, 0.25 + 0.5 * eclat * eclat)
		else:
			Trace.halo(c, q, 34.0, PAL.heal, 0.5 + 0.15 * sin(t * 3.0))

## Colonne de lumière du butin, façon Diablo : plus haute pour les raretés élevées.
func _colonne(c: CanvasItem, p: Vector2, couleur: Color, hauteur: float, souffle: float) -> void:
	var rien := Trace.voile(couleur, 0.0)
	Trace.degrade_vertical(c, Rect2(p.x - 11.0, p.y - hauteur, 22.0, hauteur + 8.0), rien, Trace.voile(couleur, 0.45 * souffle))
	Trace.degrade_vertical(c, Rect2(p.x - 3.0, p.y - hauteur * 0.85, 6.0, hauteur * 0.85 + 8.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.4 * souffle))

## Étincelles qui montent autour de l'objet (fonction du temps, sans état).
func _etincelles(c: CanvasItem, p: Vector2, couleur: Color, t: float) -> void:
	for i in ETINCELLES:
		var k := float(i)
		var vie := fposmod(t * (0.35 + 0.05 * k) + k * 0.37, 1.0)
		var q := p + Vector2(sin(k * 2.4 + t * 0.8) * (14.0 + 5.0 * k), 14.0 - 62.0 * vie)
		var a := sin(vie * PI)
		Trace.halo(c, q, 7.0, couleur, 0.6 * a)
		Trace.halo(c, q, 2.2, Color.WHITE, a)
