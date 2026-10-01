extends Node2D
## Base d'un calque du Monde : un nœud par rôle, redessiné à chaque image, qui LIT la partie.
## Les calques héritent de ce script (`extends "res://jeu/monde/calque.gd"`) et n'écrivent que
## leur `_draw`.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Trace = preload("res://jeu/monde/trace.gd")
const PAL: Dictionary = Couleurs.PAL

var monde: Node2D
var partie: Node

func relier(p_monde: Node2D, p_partie: Node) -> void:
	monde = p_monde
	partie = p_partie

## L'état de la simulation, ou null hors partie.
func etat():
	return partie.game if partie != null else null

## Horloge d'animation du Monde (s), figée pendant la pause.
func temps() -> float:
	return monde.temps if monde != null else 0.0

func _process(_delta: float) -> void:
	queue_redraw()

## Clignotement accéléré dans le dernier quart d'un télégraphe : « ça part ».
static func alerte(progression: float) -> float:
	if progression < 0.75:
		return 1.0
	return 0.75 + 0.25 * sin(progression * 60.0)
