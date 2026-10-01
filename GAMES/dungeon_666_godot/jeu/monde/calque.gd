extends Node2D
## Base d'un calque du Monde : un nœud par rôle, redessiné à chaque image, qui LIT la partie.
## Les calques héritent de ce script (`extends "res://jeu/monde/calque.gd"`) et n'écrivent que
## leur `_draw`. Un calque qui définit `_dessiner_lumieres(c: CanvasItem)` reçoit en plus un
## calque enfant en mélange ADDITIF (ses halos, ses lueurs) : la lumière s'ajoute au décor au
## lieu de le recouvrir, c'est ce qui fait « braise » sans post-traitement.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Trace = preload("res://jeu/monde/trace.gd")
const Ambiance = preload("res://jeu/monde/ambiance.gd")
const PAL: Dictionary = Couleurs.PAL

## Murs d'enceinte, vus comme les parois d'une fosse : leur face intérieure s'évase vers
## l'extérieur de la salle. Profondeur dessinée de chaque face, et largeur du dessus (u).
const FACE_NORD := 64.0
const FACE_COTE := 44.0
const FACE_SUD := 44.0
const DESSUS := 34.0

var monde: Node2D
var partie: Node
## Lumières du calque devant ses formes (défaut) ou derrière elles.
var lumieres_derriere := false

var _lumieres: Node2D = null

func relier(p_monde: Node2D, p_partie: Node) -> void:
	monde = p_monde
	partie = p_partie
	if has_method("_dessiner_lumieres") and _lumieres == null:
		_lumieres = Node2D.new()
		_lumieres.name = "Lumieres"
		var additif := CanvasItemMaterial.new()
		additif.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_lumieres.material = additif
		_lumieres.show_behind_parent = lumieres_derriere
		_lumieres.draw.connect(_sur_dessin_des_lumieres)
		add_child(_lumieres)

func _sur_dessin_des_lumieres() -> void:
	if etat() != null:
		call("_dessiner_lumieres", _lumieres)

## L'état de la simulation, ou null hors partie.
func etat():
	return partie.game if partie != null else null

## Horloge d'animation du Monde (s), figée pendant la pause.
func temps() -> float:
	return monde.temps if monde != null else 0.0

func _process(_delta: float) -> void:
	redessiner()

func redessiner() -> void:
	queue_redraw()
	if _lumieres != null:
		_lumieres.queue_redraw()

## L'intérieur de la salle : le rectangle où l'on marche.
static func dedans(room: Dictionary) -> Rect2:
	return Rect2(room.pad, room.pad, room.w - 2.0 * room.pad, room.h - 2.0 * room.pad)

## Clignotement accéléré dans le dernier quart d'un télégraphe : « ça part ».
static func alerte(progression: float) -> float:
	if progression < 0.75:
		return 1.0
	return 0.75 + 0.25 * sin(progression * 60.0)
