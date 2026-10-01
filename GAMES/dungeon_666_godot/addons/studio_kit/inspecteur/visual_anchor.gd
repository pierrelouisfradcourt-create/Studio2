class_name StudioVisualAnchor
extends RefCounted

## VisualAnchor — le REGISTRE DES DESSINS. Un jeu qui dessine sans nœuds (dans _draw) ne laisse rien à
## mesurer après coup ; recalculer ses positions serait risqué (certaines fonctions de dessin font avancer
## des animations). Alors le jeu NOTE, au moment où il dessine, où il pose chaque chose : son ancre (le
## point d'appui : les pieds d'un chat, le pied d'un arbre) et son rectangle, en coordonnées d'ÉCRAN.
##
## Éteint par défaut : noter() ne fait qu'un test et rend la main (coût nul pour le joueur). L'inspecteur
## l'allume ; un test peut l'allumer. Observation seule : rien n'est dessiné ni modifié.
##   func _draw() -> void:
##       …
##       StudioVisualAnchor.noter(self, "arbre_3", "decor", pied_local, rect_local)

static var _actif := false
static var _notes: Dictionary = {}


static func activer(oui: bool = true) -> void:
	_actif = oui
	if not oui:
		_notes.clear()


static func actif() -> bool:
	return _actif


## Note le dessin `id` : `ancre` et `rect` dans le repère LOCAL du CanvasItem qui dessine (celui de _draw).
## `infos` : ce que le dessin sait de lui-même (l'image choisie, la part visible après rognage…).
static func noter(ci: CanvasItem, id: String, type: String, ancre: Vector2, rect: Rect2 = Rect2(), infos: Dictionary = {}) -> void:
	if not _actif:
		return
	var t := ci.get_global_transform()
	_notes[id] = {"id": id, "type": type, "ecran": t * ancre, "rect": t * rect, "image": Engine.get_process_frames(), "infos": infos.duplicate()}


## Les dessins notés (copie). `depuis_image` : seulement ceux dessinés à partir de cette image.
static func notes(depuis_image: int = 0) -> Dictionary:
	var out := {}
	for id in _notes:
		if int(_notes[id]["image"]) >= depuis_image:
			out[id] = (_notes[id] as Dictionary).duplicate()
	return out


static func note(id: String) -> Dictionary:
	return (_notes.get(id, {}) as Dictionary).duplicate()


static func vider() -> void:
	_notes.clear()
