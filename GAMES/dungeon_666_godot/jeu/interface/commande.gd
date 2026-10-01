extends Control
## Une commande du héros (dash, compétence, gadget, Super, attaque) : disque, pictogramme du kit,
## recharge et charges en ANNEAU autour du bouton. Sert aux deux présentations : posée par un
## conteneur (rangée du bureau) ou placée par `placer()` (commandes tactiles).
## Ne lit pas la simulation : on lui donne son état (etat_commandes.gd) par `montrer()`.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Icones = preload("res://jeu/interface/icones.gd")

const MARGE := 9.0 # place de l'anneau autour du disque
const ANNEAU := 4.0 # épaisseur des anneaux
const ECART := 0.14 # rad entre deux segments de charge
const POULS := 0.3 # s : onde quand la commande redevient prête
const FOND := 0.72 # opacité du disque : le pictogramme se lit sur un sol clair comme sur un sol noir
const CERNE := 5.0 # px du cerne sombre sous le cercle clair

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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * (rayon + MARGE) * 2.0

## Place le bouton en pixels du viewport (centre et rayon donnés par la vue Entrees).
func placer(centre: Vector2, r: float) -> void:
	rayon = r
	size = custom_minimum_size
	position = centre - size / 2.0

func montrer(etat: Dictionary, appuye: bool = false, visee: Vector2 = Vector2.ZERO) -> void:
	if float(etat.get("pret", 1.0)) >= 1.0 and float(_etat.get("pret", 1.0)) < 1.0:
		_pouls = POULS
	_etat = etat
	_appuye = appuye
	_visee = visee
	queue_redraw()

func _process(delta: float) -> void:
	_temps += delta
	_pouls = maxf(0.0, _pouls - delta)

func _pret() -> bool:
	return float(_etat.get("pret", 1.0)) >= 1.0

func _draw() -> void:
	var c := size / 2.0
	var texte: Color = Couleurs.PAL.text
	if _etat.get("eclat", false):
		draw_circle(c, rayon + 8.0 + 3.0 * sin(_temps * 8.0), Color(Couleurs.PAL.superBar, 0.35), true, -1.0, true)
	var r := rayon * (0.94 if _appuye else 1.0)
	var encre: Color = Couleurs.UI["void"]
	draw_circle(c, r, Color(Couleurs.UI.panel, FOND), true, -1.0, true)
	if _appuye:
		draw_circle(c, r, Color(texte, 0.3), true, -1.0, true)
	# Un cerne sombre sous le cercle clair : le bouton se détache d'un fond clair (flash, lave).
	draw_arc(c, r + 0.5, 0.0, TAU, 48, Color(encre, 0.6), CERNE, true)
	draw_arc(c, r, 0.0, TAU, 48, Color(texte, 0.85 if _pret() else 0.35), 2.5, true)
	_dessiner_recharge(c)
	var plein: Color = Couleurs.PAL.superBar if id == "super" else texte
	Icones.dessiner(self, _etat.get("icone", id), c, rayon, plein if _pret() else Color(texte, 0.4))
	_dessiner_anneau(c)
	_dessiner_reactions(c)

## Secteur sombre qui se vide dans le sens horaire pendant la recharge.
func _dessiner_recharge(c: Vector2) -> void:
	var pret: float = _etat.get("pret", 1.0)
	if pret >= 1.0:
		return
	var pts := PackedVector2Array([c])
	var a0 := -PI / 2.0 + TAU * pret
	for i in range(33):
		pts.append(c + Vector2.from_angle(lerpf(a0, -PI / 2.0 + TAU, i / 32.0)) * rayon)
	draw_colored_polygon(pts, Color(Couleurs.UI["void"], 0.55))

## Anneau : charges en segments (dash, gadget) ou jauge continue (compétence, Super).
func _dessiner_anneau(c: Vector2) -> void:
	var rr := rayon + ANNEAU
	var maxi := int(_etat.get("max", 0.0))
	if maxi > 0:
		_dessiner_charges(c, rr, maxi, Couleurs.PAL.dashPip if id == "dash" else Couleurs.PAL.gold)
		return
	var pret: float = _etat.get("pret", 1.0)
	if id == "super" or (id == "skill" and pret < 1.0):
		var col: Color = Couleurs.PAL.superBar if id == "super" else Couleurs.PAL.lance
		draw_arc(c, rr, 0.0, TAU, 48, Color(Couleurs.PAL.text, 0.12), ANNEAU, true)
		if pret > 0.01:
			draw_arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * pret, 48, col, ANNEAU, true)

func _dessiner_charges(c: Vector2, rr: float, maxi: int, col: Color) -> void:
	var seg := TAU / maxi
	var ecart := ECART if maxi > 1 else 0.0
	var charges := int(_etat.get("charges", 0.0))
	var partiel: float = _etat.get("partiel", 0.0)
	for i in range(maxi):
		var a0 := -PI / 2.0 + i * seg + ecart / 2.0
		var a1 := a0 + seg - ecart
		draw_arc(c, rr, a0, a1, 24, col if i < charges else Color(Couleurs.PAL.text, 0.18), ANNEAU, true)
		if i == charges and partiel > 0.0:
			draw_arc(c, rr, a0, lerpf(a0, a1, minf(1.0, partiel)), 24, Color(col, 0.55), ANNEAU, true)

## Onde « prêt ! » et repère de visée quand le pouce glisse (attaque, compétence).
func _dessiner_reactions(c: Vector2) -> void:
	if _pouls > 0.0:
		var k := 1.0 - _pouls / POULS
		draw_arc(c, rayon + ANNEAU + 10.0 * k, 0.0, TAU, 48, Color(Couleurs.PAL.text, 0.6 * (1.0 - k)), 2.0, true)
	if _visee.length_squared() > 1.0:
		var d := _visee.normalized()
		draw_line(c + d * rayon * 0.55, c + d * (rayon + ANNEAU), Couleurs.PAL.slashStrike, 3.0, true)
		draw_circle(c + d * (rayon + ANNEAU + 5.0), 5.0, Couleurs.PAL.slashStrike, true, -1.0, true)
