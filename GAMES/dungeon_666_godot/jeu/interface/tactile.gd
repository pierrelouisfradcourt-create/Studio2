extends Control
## Les commandes TACTILES du combat V3 : le joystick flottant, le gros bouton d'attaque, les trois
## emplacements en arc autour de lui et le dash à part, DESSINÉS aux positions que donne la vue
## Entrees (`interface_tactile()`, en pixels du viewport), et la LIGNE DE VISÉE qui part du héros
## quand le pouce glisse sur l'attaque ou sur un emplacement qui se vise. Ce nœud ne lit aucun
## toucher : la vue Entrees s'en charge.
## Coût : un appel de dessin par bouton, un pour le joystick et la ligne de visée ensemble.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Etats = preload("res://jeu/interface/etat_commandes.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const COURSE := 58.0 # rayon de la base du joystick
const POUCE := 26.0
const DEGAGEMENT := 24.0 # px autour du groupe de boutons
const RAYON_ATTAQUE := 52.0 # rayon de référence du bouton d'attaque (px CSS) : donne l'échelle
## La ligne de visée, en px CSS : elle commence hors du héros, finit par une pointe. Elle montre
## une DIRECTION, pas une portée (la portée est une règle : l'affichage ne la calcule pas).
const VISEE := {"debut": 30.0, "fin": 170.0, "trait": 5.0, "pointe": 13.0}

@onready var _boutons := {"attack": $Attaque, "dash": $Dash, "skill1": $Emplacement1, "skill2": $Emplacement2, "skill3": $Emplacement3}

var _manette := {}
var _coin := Vector2.INF
var _visee := {} # {de, dir, couleur} : la ligne de visée à dessiner, ou vide
var _echelle := 1.0

## `designee` : la commande que nomme la consigne de l'accueil ("" : aucune) ; son bouton bat.
## `heros` : la position du héros à l'écran (départ de la ligne de visée).
func actualiser(game: Dictionary, ui: Dictionary, designee: String = "", heros: Vector2 = Vector2.INF) -> void:
	_manette = ui.get("stick", {})
	_coin = Vector2.INF
	_visee = {}
	for b in ui.get("buttons", []):
		var bouton: Control = _boutons.get(b.id)
		if bouton == null:
			continue
		var etat: Dictionary = Etats.etat(game, b.id)
		var glisse := Vector2(b.get("dx", 0.0), b.get("dy", 0.0)) if D6Js.truthy(b.get("dragging")) else Vector2.ZERO
		bouton.placer(Vector2(b.x, b.y), b.r)
		bouton.montrer(etat, D6Js.truthy(b.get("pressed")), glisse)
		bouton.designer(b.id == designee)
		_coin = _coin.min(Vector2(b.x - b.r, b.y - b.r))
		if b.id == "attack":
			_echelle = b.r / RAYON_ATTAQUE
		if glisse != Vector2.ZERO and heros.is_finite() and _se_vise(b.id, etat):
			_visee = {"de": heros, "dir": glisse.normalized(), "couleur": Couleurs.PAL.slashStrike if b.id == "attack" else Couleurs.PAL.lance}
	queue_redraw()

## L'attaque se vise toujours ; un emplacement, seulement si son action se vise (et s'il en a une).
static func _se_vise(id: String, etat: Dictionary) -> bool:
	return id == "attack" or (etat.get("visee", false) and not etat.get("vide", false))

## La ligne de visée montrée ({de, dir, couleur}), ou un dictionnaire vide (pour les essais).
func visee() -> Dictionary:
	return _visee

## Coin haut-gauche du groupe de boutons : rien d'autre ne doit s'y poser.
func coin() -> Vector2:
	return _coin - Vector2.ONE * DEGAGEMENT if _coin.is_finite() else size

func _draw() -> void:
	var lot := Triangles.new()
	if not _visee.is_empty():
		_dessiner_visee(lot)
	if D6Js.truthy(_manette.get("active")):
		_dessiner_manche(lot)
	lot.tracer(self)

## Cerne sombre puis trait clair : la ligne se lit sur un sol clair comme sur un sol noir.
func _dessiner_visee(lot: Triangles) -> void:
	var dir: Vector2 = _visee.dir
	var a: Vector2 = _visee.de + dir * VISEE.debut * _echelle
	var b: Vector2 = _visee.de + dir * VISEE.fin * _echelle
	var ep: float = VISEE.trait * _echelle
	var t: float = VISEE.pointe * _echelle
	var pointe := PackedVector2Array([b + dir * t, b + dir.orthogonal() * t * 0.7, b - dir.orthogonal() * t * 0.7])
	var encre := Color(Couleurs.UI["void"], 0.5)
	lot.ligne(a, b, encre, ep + 4.0)
	lot.contour(pointe, encre, 4.0)
	lot.ligne(a, b, Color(_visee.couleur, 0.9), ep)
	lot.polygone(pointe, _visee.couleur)

## Cerne sombre puis trait clair : le joystick se lit sur un sol clair comme sur un sol noir.
func _dessiner_manche(lot: Triangles) -> void:
	var blanc: Color = Couleurs.PAL.text
	var encre: Color = Couleurs.UI["void"]
	var base := Vector2(_manette.baseX, _manette.baseY)
	var pouce := Vector2(_manette.knobX, _manette.knobY)
	lot.disque(base, COURSE, Color(encre, 0.22))
	lot.arc(base, COURSE + 0.5, 0.0, TAU, 48, Color(encre, 0.45), 4.5)
	lot.arc(base, COURSE, 0.0, TAU, 48, Color(blanc, 0.45), 2.0)
	lot.disque(pouce, POUCE + 1.5, Color(encre, 0.45))
	lot.disque(pouce, POUCE, Color(blanc, 0.5))
