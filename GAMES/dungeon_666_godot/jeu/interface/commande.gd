extends Control
## Une commande du héros (attaque, dash, emplacement d'action), dessinée. Sert aux trois
## présentations : posée par un conteneur (rangée du bureau, Grimoire) ou placée par `placer()`
## (commandes tactiles). Trois dessins, selon l'état reçu :
##   - l'ATTAQUE est la JAUGE D'ULTIME : un niveau monte DANS le bouton (repères au quart, à la
##     moitié, aux trois quarts) ; pleine, le bouton devient braise, son pictogramme passe au
##     sombre et un halo bat ; tant que l'attaque est maintenue jauge pleine, un anneau clair se
##     FERME autour du bouton (il disparaît si on relâche) ;
##   - un EMPLACEMENT ou le DASH : pictogramme du kit, recharge en balayage (secteur sombre qui se
##     vide) et en anneau, ou charges en segments autour du bouton ; prêt = cercle et pictogramme
##     clairs, une onde au moment où il le redevient ;
##     une action qui se BANDE (charge) : un anneau d'or se remplit dans le disque ; un effet qui
##     DURE (durée) : un anneau froid s'y vide ;
##   - un emplacement VIDE : un socle éteint, cerclé de tirets, sans pictogramme ni réaction.
## Ne lit pas la simulation : on lui donne son état (etat_commandes.gd) par `montrer()`.
## Coût : tout le bouton (disque, niveau, cernes, pictogramme, anneaux) part en UN appel de dessin.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Icones = preload("res://jeu/interface/icones.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")

const MARGE := 9.0 # place de l'anneau autour du disque
const ANNEAU := 4.0 # épaisseur des anneaux
const ECART := 0.14 # rad entre deux segments de charge
const POULS := 0.3 # s : onde quand la commande redevient prête
const FOND := 0.72 # opacité du disque : le pictogramme se lit sur un sol clair comme sur un sol noir
const CERNE := 5.0 # px du cerne sombre sous le cercle clair
const DESIGNEE := Vector3(6.0, 2.5, 6.0) # anneau d'une commande désignée : écart, battement (px), vitesse
const PALIERS := 48 # crans du niveau de la jauge (un gabarit de polygone par cran, pas par image)
const REPERES := [0.25, 0.5, 0.75] # petits traits au bord : la jauge se lit d'un coup d'œil
const NIVEAU := 0.62 # opacité du niveau qui monte (le pictogramme clair reste lisible dessus)
const HALO := Vector3(7.0, 3.0, 7.0) # jauge pleine : écart du halo, battement (px), vitesse
const MAINTIEN := 5.0 # épaisseur de l'anneau qui se ferme pendant le maintien
const TIRETS := 12 # tirets du cercle d'un emplacement vide
const DEDANS := 4.5 # l'anneau de charge ou de durée court DANS le disque, à cette distance du bord

@export var id := "dash"
@export var rayon := 22.0:
	set(v):
		rayon = v
		custom_minimum_size = Vector2.ONE * (v + MARGE) * 2.0

var _etat := {"pret": 1.0}
var _appuye := false
var _visee := Vector2.ZERO
var _temps := 0.0
var _pouls := 0.0
var _designee := false
var _lot := Triangles.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * (rayon + MARGE) * 2.0

## Place le bouton en pixels du viewport (centre et rayon donnés par la vue Entrees).
func placer(centre: Vector2, r: float) -> void:
	rayon = r
	size = custom_minimum_size
	position = centre - size / 2.0

## `appuye` : un doigt tient le bouton ; `visee` : il a glissé (direction du pouce). Un
## emplacement vide ne réagit à rien.
func montrer(etat: Dictionary, appuye: bool = false, visee: Vector2 = Vector2.ZERO) -> void:
	if float(etat.get("pret", 1.0)) >= 1.0 and float(_etat.get("pret", 1.0)) < 1.0:
		_pouls = POULS
	var vide: bool = etat.get("vide", false)
	_etat = etat
	_appuye = appuye and not vide
	_visee = Vector2.ZERO if vide else visee
	queue_redraw()

## Une consigne de l'accueil nomme cette commande : un anneau doré bat autour du bouton.
func designer(oui: bool) -> void:
	if oui != _designee:
		_designee = oui
		queue_redraw()

func _process(delta: float) -> void:
	_temps += delta
	_pouls = maxf(0.0, _pouls - delta)

func _pret() -> bool:
	return float(_etat.get("pret", 1.0)) >= 1.0

func _draw() -> void:
	var c := size / 2.0
	if _etat.get("vide", false):
		_dessiner_vide(c)
	elif _etat.has("jauge"):
		_dessiner_jauge(c)
	else:
		_dessiner_bouton(c)
	_dessiner_reactions(c)
	_lot.tracer(self)

# ---------------------------------------------------------------- les trois dessins

## Emplacement ou dash : disque, balayage de recharge, pictogramme, anneau.
func _dessiner_bouton(c: Vector2) -> void:
	var texte: Color = Couleurs.PAL.text
	var r := _socle(c)
	_lot.arc(c, r, 0.0, TAU, 48, Color(texte, 0.85 if _pret() else 0.35), 2.5)
	_dessiner_recharge(c)
	var icone: String = _etat.get("icone", id)
	if icone != "":
		Icones.ajouter(_lot, icone, c, rayon, texte if _pret() else Color(texte, 0.4))
	_dessiner_anneau(c)
	_dessiner_etat(c, r)

## Le bouton d'attaque, jauge d'ultime : le niveau monte dans le disque ; pleine, tout le bouton
## est braise et bat ; maintenue, un anneau se ferme autour.
func _dessiner_jauge(c: Vector2) -> void:
	var braise: Color = Couleurs.PAL.superBar
	var jauge: float = clampf(_etat.jauge, 0.0, 1.0)
	var pleine: bool = jauge >= 1.0
	if pleine:
		var bat := snappedf(HALO.y * sin(_temps * HALO.z), 0.25)
		_lot.disque(c, rayon + HALO.x + bat, Color(braise, 0.32))
	var r := _socle(c)
	if pleine:
		_lot.disque(c, r, braise)
	elif jauge > 0.0:
		_dessiner_niveau(c, r, jauge)
	_dessiner_reperes(c, r, pleine)
	_lot.arc(c, r, 0.0, TAU, 48, Couleurs.PAL.gold if pleine else Color(Couleurs.PAL.text, 0.85), 3.5 if pleine else 2.5)
	var icone: String = _etat.get("icone", id)
	if icone != "":
		Icones.ajouter(_lot, icone, c, rayon, Couleurs.UI["void"] if pleine else Couleurs.PAL.text)
	var maintien: float = _etat.get("maintien", 0.0)
	if maintien > 0.0:
		var rr := rayon + MARGE - MAINTIEN * 0.5 - 0.5
		_lot.arc(c, rr, 0.0, TAU, 48, Color(Couleurs.UI["void"], 0.6), MAINTIEN + 2.0)
		_lot.arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * minf(1.0, maintien), 48, Couleurs.PAL.text, MAINTIEN)

## Emplacement vide : un socle éteint, cerclé de tirets.
func _dessiner_vide(c: Vector2) -> void:
	_lot.disque(c, rayon, Color(Couleurs.UI.panel, 0.4))
	var pas := TAU / TIRETS
	for i in TIRETS:
		_lot.arc(c, rayon, i * pas, (i + 0.5) * pas, 6, Color(Couleurs.PAL.text, 0.22), 2.0)

# ---------------------------------------------------------------- pièces

## Le disque sombre, son éclaircie quand il est appuyé, et le cerne sombre sous le cercle clair
## (le bouton se détache d'un fond clair : flash, lave). Rend le rayon dessiné.
func _socle(c: Vector2) -> float:
	var r := rayon * (0.94 if _appuye else 1.0)
	_lot.disque(c, r, Color(Couleurs.UI.panel, FOND))
	if _appuye:
		_lot.disque(c, r, Color(Couleurs.PAL.text, 0.3))
	_lot.arc(c, r + 0.5, 0.0, TAU, 48, Color(Couleurs.UI["void"], 0.6), CERNE)
	return r

## Le niveau de la jauge : la part basse du disque, jusqu'à la hauteur `jauge` (0 = fond, 1 =
## sommet), et sa surface en trait clair.
func _dessiner_niveau(c: Vector2, r: float, jauge: float) -> void:
	var cran := clampf(roundf(jauge * PALIERS), 1.0, PALIERS - 1.0) / PALIERS
	var a := asin(1.0 - 2.0 * cran) # angle du bord droit de la surface (y vers le bas)
	var pts := PackedVector2Array()
	for i in range(25):
		pts.append(Vector2.from_angle(lerpf(a, PI - a, i / 24.0)) * r)
	_lot.polygone(pts, Color(Couleurs.PAL.superBar, NIVEAU), Transform2D(0.0, c))
	_lot.ligne(c + pts[0], c + pts[24], Couleurs.PAL.superBar, 2.5)

## Repères du quart, de la moitié et des trois quarts, de chaque côté, contre le bord.
func _dessiner_reperes(c: Vector2, r: float, pleine: bool) -> void:
	var col := Color(Couleurs.UI["void"], 0.55) if pleine else Color(Couleurs.PAL.text, 0.6)
	for part: float in REPERES:
		var a := asin(1.0 - 2.0 * part)
		var bord := Vector2.from_angle(a) * r
		var dedans := Vector2(bord.x - r * 0.2, bord.y)
		_lot.ligne(c + bord, c + dedans, col, 2.0)
		_lot.ligne(c + Vector2(-bord.x, bord.y), c + Vector2(-dedans.x, dedans.y), col, 2.0)

## Secteur sombre qui se vide dans le sens horaire pendant la recharge.
func _dessiner_recharge(c: Vector2) -> void:
	var pret: float = _etat.get("pret", 1.0)
	if pret >= 1.0:
		return
	var pts := PackedVector2Array([c])
	var a0 := -PI / 2.0 + TAU * pret
	for i in range(33):
		pts.append(c + Vector2.from_angle(lerpf(a0, -PI / 2.0 + TAU, i / 32.0)) * rayon)
	_lot.polygone(pts, Color(Couleurs.UI["void"], 0.55))

## Ce que l'action fait EN CE MOMENT (lu par etat_commandes dans D6Loadout.slot_state), dans le
## disque : elle se bande — un anneau d'or se REMPLIT ; son effet dure — un anneau froid se VIDE.
func _dessiner_etat(c: Vector2, r: float) -> void:
	var charge: float = _etat.get("charge", 0.0)
	var duree: float = _etat.get("duree", 0.0)
	if charge <= 0.0 and duree <= 0.0:
		return
	var rr := r - DEDANS
	var part := clampf(charge if charge > 0.0 else duree, 0.0, 1.0)
	_lot.arc(c, rr, 0.0, TAU, 48, Color(Couleurs.UI["void"], 0.55), ANNEAU + 1.5)
	if part > 0.01:
		_lot.arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * part, 48, Couleurs.PAL.gold if charge > 0.0 else Couleurs.PAL.slashStrike, ANNEAU)

## Anneau : charges en segments (dash, gadget) ou recharge continue (compétence).
func _dessiner_anneau(c: Vector2) -> void:
	var rr := rayon + ANNEAU
	var maxi := int(_etat.get("max", 0.0))
	if maxi > 0:
		_dessiner_charges(c, rr, maxi, Couleurs.PAL.dashPip if id == "dash" else Couleurs.PAL.gold)
		return
	var pret: float = _etat.get("pret", 1.0)
	if _etat.get("recharge", false) and pret < 1.0:
		_lot.arc(c, rr, 0.0, TAU, 48, Color(Couleurs.PAL.text, 0.12), ANNEAU)
		if pret > 0.01:
			_lot.arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * pret, 48, Couleurs.PAL.lance, ANNEAU)

func _dessiner_charges(c: Vector2, rr: float, maxi: int, col: Color) -> void:
	var seg := TAU / maxi
	var ecart := ECART if maxi > 1 else 0.0
	var charges := int(_etat.get("charges", 0.0))
	var partiel: float = _etat.get("partiel", 0.0)
	for i in range(maxi):
		var a0 := -PI / 2.0 + i * seg + ecart / 2.0
		var a1 := a0 + seg - ecart
		_lot.arc(c, rr, a0, a1, 24, col if i < charges else Color(Couleurs.PAL.text, 0.18), ANNEAU)
		if i == charges and partiel > 0.0:
			_lot.arc(c, rr, a0, lerpf(a0, a1, minf(1.0, partiel)), 24, Color(col, 0.55), ANNEAU)

## Anneau doré d'une commande désignée, onde « prêt ! », et repère du pouce qui glisse (la ligne
## de visée, elle, part du héros : jeu/interface/tactile.gd).
func _dessiner_reactions(c: Vector2) -> void:
	if _designee:
		var bat := 0.5 + 0.5 * sin(_temps * DESIGNEE.z)
		_lot.arc(c, rayon + ANNEAU + DESIGNEE.x + DESIGNEE.y * bat, 0.0, TAU, 48, Color(Couleurs.PAL.gold, 0.55 + 0.45 * bat), 3.0)
	if _pouls > 0.0:
		var k := 1.0 - _pouls / POULS
		_lot.arc(c, rayon + ANNEAU + 10.0 * k, 0.0, TAU, 48, Color(Couleurs.PAL.text, 0.6 * (1.0 - k)), 2.0)
	if _visee.length_squared() > 1.0:
		var d := _visee.normalized()
		_lot.ligne(c + d * rayon * 0.55, c + d * (rayon + ANNEAU), Couleurs.PAL.slashStrike, 3.0)
		_lot.disque(c + d * (rayon + ANNEAU + 5.0), 5.0, Couleurs.PAL.slashStrike)
