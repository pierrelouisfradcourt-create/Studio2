extends "res://jeu/monde/calque.gd"
## Les portes de la salle, percées dans le mur du fond : une arche de pierre par porte. Fermée,
## une herse. Ouverte, elle s'emplit en une demi-seconde d'une lumière à la couleur de la
## récompense, qui déborde sur le cadre et coule sur le seuil (calque additif) : c'est là qu'on
## marche pour la prendre. Devant, le pictogramme dans son médaillon et le libellé.
## La porte « town » est le portail de la Ville.

const Icones = preload("res://jeu/monde/icones.gd")
const FOND := Color("#060305")
const FER := Color("#40303a")
const FER_CLAIR := Color("#7a6670")
const CALMES := {"treasure": Color("#ffb43c"), "rest": Color("#6dd8ff")}
const DEMI := 42.0 # u : demi-largeur de l'ouverture
const JAMBAGE := 14.0 # u : hauteur des pieds droits, sous la voûte
const CADRE := 10.0 # u : épaisseur du cadre de pierre
const SEUIL := 40.0 # u : profondeur de la bande où l'on prend la porte (DOOR_H de la simulation)
const DUREE_OUVERTURE := 0.5 # s

## Ouverture dessinée de chaque porte (0 = fermée, 1 = grande ouverte) : animation seulement.
var _ouvertures: Array[float] = []
var _salle = null

func _process(delta: float) -> void:
	var g = etat()
	if g != null:
		_animer(g, delta)
	redessiner()

func _animer(g: Dictionary, delta: float) -> void:
	var portes: Array = g.room.doors
	if not is_same(g.room, _salle) or _ouvertures.size() != portes.size():
		_salle = g.room
		_ouvertures.resize(portes.size())
		_ouvertures.fill(0.0)
	for i in portes.size():
		var ouverte := D6Js.truthy(portes[i].get("open"))
		_ouvertures[i] = minf(1.0, _ouvertures[i] + delta / DUREE_OUVERTURE) if ouverte else 0.0

func _ouverture(i: int) -> float:
	return _ouvertures[i] if i < _ouvertures.size() else 1.0

func _draw() -> void:
	var g = etat()
	if g == null:
		return
	var a: Dictionary = monde.ambiance()
	for i in g.room.doors.size():
		_porte(g.room.doors[i], g.room.pad, _ouverture(i), a)

func _porte(d: Dictionary, base: float, k: float, a: Dictionary) -> void:
	var ouverte := D6Js.truthy(d.get("open"))
	var couleur := couleur_de(d)
	var cx: float = d.x + d.w / 2.0
	Trace.forme(self, _arche(cx, base, DEMI + CADRE), Ambiance.eclaire(a.mur, 1.5), Trace.CERNE, 2.5)
	_claveaux(cx, base, Trace.voile(a.joint, 0.6))
	var vide := _arche(cx, base, DEMI)
	draw_colored_polygon(vide, FOND)
	if ouverte:
		_lumiere(vide, base, couleur, k)
		if d.reward == "town":
			_portail(Vector2(cx, base - JAMBAGE - 10.0), couleur, k)
	else:
		_herse(cx, base)
	draw_polyline(vide, Trace.CERNE, 5.0, true)
	draw_polyline(vide, FER_CLAIR.lerp(couleur, k) if ouverte else FER_CLAIR, 2.5, true)
	_cle(Vector2(cx, base - JAMBAGE - DEMI - CADRE * 0.5), couleur if ouverte else FER_CLAIR)
	_enseigne(d, Vector2(cx, base + SEUIL), couleur if ouverte else PAL.textDim, ouverte)

## Couleur de la récompense annoncée (une bénédiction prend celle de sa famille).
static func couleur_de(d: Dictionary) -> Color:
	var famille = d.get("family")
	if d.reward == "boon" and famille != null:
		return Color(D6Data.tables().boons.FAMILIES[famille].color)
	if Couleurs.REWARD_COLORS.has(d.reward):
		return Couleurs.REWARD_COLORS[d.reward]
	return CALMES.get(d.reward, Color.WHITE)

static func libelle_de(d: Dictionary) -> String:
	var famille = d.get("family")
	if d.reward == "boon" and famille != null:
		return D6Data.tables().boons.FAMILIES[famille].name
	return str(D6Data.tables().run.REWARD_LABELS.get(d.reward, ""))

## Tracé ouvert d'une arche de demi-largeur `demi` posée sur `base` : pied, voûte en plein cintre, pied.
func _arche(cx: float, base: float, demi: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(cx - demi, base)])
	pts.append_array(Trace.arc(Vector2(cx, base - JAMBAGE), demi, PI, TAU, 18))
	pts.append(Vector2(cx + demi, base))
	return pts

## Joints des claveaux : la voûte est faite de pierres taillées.
func _claveaux(cx: float, base: float, joint: Color) -> void:
	var centre := Vector2(cx, base - JAMBAGE)
	for i in range(1, 8):
		var u := Vector2.from_angle(PI + PI * float(i) / 8.0)
		draw_line(centre + u * DEMI, centre + u * (DEMI + CADRE), joint, 1.5)
	for s in [-1.0, 1.0]:
		draw_line(Vector2(cx + s * DEMI, base - JAMBAGE), Vector2(cx + s * (DEMI + CADRE), base - JAMBAGE), joint, 1.5)

## Porte ouverte : la lumière emplit l'arche, dense au seuil, plus rare sous la voûte.
func _lumiere(vide: PackedVector2Array, base: float, couleur: Color, k: float) -> void:
	var haut := base - JAMBAGE - DEMI
	var souffle := 0.9 + 0.1 * sin(temps() * 3.0)
	var teintes := PackedColorArray()
	for p in vide:
		var bas := clampf((p.y - haut) / (base - haut), 0.0, 1.0)
		teintes.append(Trace.voile(couleur.lerp(Color.WHITE, 0.3 * bas), (0.22 + 0.7 * bas) * k * souffle))
	draw_polygon(vide, teintes)

## Porte fermée : herse de fer sous la voûte.
func _herse(cx: float, base: float) -> void:
	var x := -DEMI + 9.0
	while x < DEMI - 2.0:
		var haut := base - JAMBAGE - sqrt(maxf(0.0, DEMI * DEMI - x * x))
		draw_line(Vector2(cx + x, haut), Vector2(cx + x, base), FER, 4.0)
		draw_line(Vector2(cx + x - 1.0, haut + 2.0), Vector2(cx + x - 1.0, base), Trace.voile(FER_CLAIR, 0.5), 1.0)
		x += 13.0
	for y in [base - 16.0, base - 38.0]:
		var l := DEMI if y > base - JAMBAGE else sqrt(maxf(0.0, DEMI * DEMI - (base - JAMBAGE - y) * (base - JAMBAGE - y)))
		draw_line(Vector2(cx - l, y), Vector2(cx + l, y), FER, 4.0)

## Clé de voûte : un cabochon à la couleur de la récompense.
func _cle(p: Vector2, couleur: Color) -> void:
	var sans := PackedVector2Array()
	draw_primitive(PackedVector2Array([p + Vector2(0, -9), p + Vector2(8, 0), p + Vector2(0, 9), p + Vector2(-8, 0)]), PackedColorArray([Trace.CERNE, Trace.CERNE, Trace.CERNE, Trace.CERNE]), sans)
	var clair := couleur.lerp(Color.WHITE, 0.5)
	draw_primitive(PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)]), PackedColorArray([clair, couleur, couleur, clair]), sans)

## Devant la porte : pictogramme dans un médaillon sombre, et libellé.
func _enseigne(d: Dictionary, p: Vector2, couleur: Color, ouverte: bool) -> void:
	var saut := sin(temps() * 3.0 + p.x * 0.01) * 2.0 if ouverte else 0.0
	var icone := p + Vector2(0, 24.0 + saut)
	Trace.halo(self, icone, 34.0, Color.BLACK, 0.85)
	draw_circle(icone, 19.0, Trace.voile(couleur, 0.5 if ouverte else 0.25), false, 1.5, true)
	Icones.recompense(self, str(d.reward), icone, 12.0, couleur)
	Trace.texte(self, p + Vector2(0, 54.0), libelle_de(d), 15, couleur)

## Portail de la Ville : anneaux qui tournent dans l'arche.
func _portail(p: Vector2, couleur: Color, k: float) -> void:
	var t := temps()
	for i in 3:
		var r := 27.0 - 8.0 * float(i)
		var a := t * (1.6 + 0.7 * float(i)) * (1.0 if i % 2 == 0 else -1.0)
		draw_arc(p, r, a, a + 4.2, 20, Trace.voile(Color.WHITE.lerp(couleur, 0.6), (0.95 - 0.2 * float(i)) * k), 3.0, true)
	draw_circle(p, 4.5 + sin(t * 5.0), Trace.voile(Color.WHITE, k), true, -1.0, true)

## La lumière des portes ouvertes (mélange additif) : lueur sur le cadre, flaque de couleur et
## bande claire sur le seuil.
func _dessiner_lumieres(c: CanvasItem) -> void:
	var g = etat()
	var base: float = g.room.pad
	for i in g.room.doors.size():
		var d: Dictionary = g.room.doors[i]
		if not D6Js.truthy(d.get("open")):
			continue
		var k := _ouverture(i)
		var couleur := couleur_de(d)
		var cx: float = d.x + d.w / 2.0
		var souffle := 0.85 + 0.15 * sin(temps() * 3.0 + cx * 0.01)
		Trace.halo(c, Vector2(cx, base - 30.0), 82.0, couleur, 0.4 * k * souffle)
		Trace.halo_ovale(c, Vector2(cx, base + 30.0), 130.0, 74.0, couleur, 0.42 * k * souffle)
		var pres := Trace.voile(couleur, 0.5 * k * souffle)
		var loin := Trace.voile(couleur, 0.0)
		var seuil := PackedVector2Array([Vector2(cx - DEMI, base), Vector2(cx + DEMI, base), Vector2(cx + DEMI + 22.0, base + SEUIL + 26.0), Vector2(cx - DEMI - 22.0, base + SEUIL + 26.0)])
		c.draw_primitive(seuil, PackedColorArray([pres, pres, loin, loin]), PackedVector2Array())
		if d.reward == "town":
			Trace.halo(c, Vector2(cx, base - JAMBAGE - 10.0), 46.0, Color.WHITE, 0.5 * k)
