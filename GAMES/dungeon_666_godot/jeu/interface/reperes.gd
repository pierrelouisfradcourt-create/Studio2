extends Control
## Les REPÈRES tracés sur le monde par le HUD, autour du héros :
##   - la LIGNE DE VISÉE d'une compétence qui se vise. Au doigt, c'est la vue des commandes
##     tactiles qui la trace (jeu/interface/tactile.gd, par `ajouter_visee`) ; au clavier et à la
##     manette, c'est ce nœud, tant que la touche de l'emplacement est enfoncée ;
##   - le POINT D'ARRIVÉE d'un déplacement de classe qui serait RACCOURCI par une rivière ou un
##     obstacle bas (D6Player.move_landing, `full == false`) : un petit anneau au sol, là où le
##     héros se poserait, tant qu'il marche vers l'eau. Rien quand le geste irait au bout.
## Ce nœud ne lit rien : le HUD lui donne des positions d'écran. Coût : un appel de dessin.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
## La ligne de visée, en px CSS : elle commence hors du héros, finit par une pointe. Elle montre
## une DIRECTION, pas une portée (la portée est une règle : l'affichage ne la calcule pas).
const VISEE := {"debut": 30.0, "fin": 170.0, "trait": 5.0, "pointe": 13.0}
## Le point d'arrivée raccourci, en px CSS : rayon de l'anneau, épaisseur, demi-longueur de la barre.
const ARRIVEE := {"rayon": 9.0, "trait": 2.5, "barre": 5.0, "opacite": 0.75}

var _visee := {} # {de, dir, couleur}, ou vide
var _arrivee := Vector2.INF # position d'écran, ou INF : rien
var _echelle := 1.0

## `visee` : {de, dir, couleur} ou vide ; `arrivee` : position d'écran du point d'arrivée
## raccourci, ou Vector2.INF ; `echelle` : celle des commandes à l'écran.
func montrer(visee_: Dictionary, arrivee_: Vector2, echelle: float) -> void:
	if visee_ == _visee and arrivee_ == _arrivee and echelle == _echelle:
		return
	_visee = visee_
	_arrivee = arrivee_
	_echelle = echelle
	queue_redraw()

## Pour les essais : la ligne montrée ({de, dir, couleur} ou vide), le point d'arrivée (ou INF).
func visee() -> Dictionary:
	return _visee

func arrivee() -> Vector2:
	return _arrivee

func _draw() -> void:
	var lot := Triangles.new()
	if _arrivee.is_finite():
		_dessiner_arrivee(lot)
	if not _visee.is_empty():
		ajouter_visee(lot, _visee, _echelle)
	lot.tracer(self)

## Anneau barré, cerné de sombre : « tu t'arrêteras ici ». Discret : ni plein, ni clignotant.
func _dessiner_arrivee(lot: Triangles) -> void:
	var r: float = ARRIVEE.rayon * _echelle
	var ep: float = ARRIVEE.trait * _echelle
	var barre := Vector2(ARRIVEE.barre * _echelle, 0.0)
	var encre := Color(Couleurs.UI["void"], 0.5)
	var col := Color(Couleurs.PAL.danger, ARRIVEE.opacite)
	lot.arc(_arrivee, r, 0.0, TAU, 24, encre, ep + 3.0)
	lot.ligne(_arrivee - barre, _arrivee + barre, encre, ep + 3.0)
	lot.arc(_arrivee, r, 0.0, TAU, 24, col, ep)
	lot.ligne(_arrivee - barre, _arrivee + barre, col, ep)

## La ligne de visée `v` ({de, dir, couleur}) ajoutée au lot : cerne sombre puis trait clair, elle
## se lit sur un sol clair comme sur un sol noir. La même au doigt, au clavier et à la manette.
static func ajouter_visee(lot: Triangles, v: Dictionary, echelle: float) -> void:
	var dir: Vector2 = v.dir
	var a: Vector2 = v.de + dir * VISEE.debut * echelle
	var b: Vector2 = v.de + dir * VISEE.fin * echelle
	var ep: float = VISEE.trait * echelle
	var t: float = VISEE.pointe * echelle
	var pointe := PackedVector2Array([b + dir * t, b + dir.orthogonal() * t * 0.7, b - dir.orthogonal() * t * 0.7])
	var encre := Color(Couleurs.UI["void"], 0.5)
	lot.ligne(a, b, encre, ep + 4.0)
	lot.contour(pointe, encre, 4.0)
	lot.ligne(a, b, Color(v.couleur, 0.9), ep)
	lot.polygone(pointe, v.couleur)
