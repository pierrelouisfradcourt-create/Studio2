# touch_input.gd — SOURCE D'INTENTIONS TACTILE (lignes touch.pause_surface,
# touch.no_logic_touch).
#
# Le tactile est une source d'intentions DE PLUS dans la couche d'entree : son ajout
# n'ouvre AUCUN chemin de pause parallele (la transition unique appartient a app_state),
# n'introduit aucune notion de doigt ni d'ecran dans la logique, et ne touche aucun
# fichier de 05_SYSTEMS.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")

# SURFACE DECLAREE du bouton de pause, en pixels, ancree au coin haut droit de la
# fenetre. Declaree ici — la logique n'en sait rien et n'en saura jamais rien.
const MARGE: int = 8
const LARGEUR_BOUTON: int = 56
const HAUTEUR_BOUTON: int = 32

# Surfaces directionnelles : quatre quarts d'un pave ancre au coin bas gauche.
const COTE_PAVE: int = 144
const MARGE_PAVE: int = 12


static func surface_pause(largeur_fenetre: int) -> Rect2i:
	return Rect2i(largeur_fenetre - LARGEUR_BOUTON - MARGE, MARGE, LARGEUR_BOUTON, HAUTEUR_BOUTON)


static func surface_dash(largeur_fenetre: int, hauteur_fenetre: int) -> Rect2i:
	return Rect2i(
		largeur_fenetre - LARGEUR_BOUTON - MARGE,
		hauteur_fenetre - HAUTEUR_BOUTON - MARGE,
		LARGEUR_BOUTON, HAUTEUR_BOUTON)


# Pave directionnel : quatre zones nommees, deux a deux disjointes.
static func surfaces_directions(hauteur_fenetre: int) -> Dictionary:
	var base_y: int = hauteur_fenetre - COTE_PAVE - MARGE_PAVE
	var tiers: int = COTE_PAVE / 3
	return {
		Bindings.ZONE_HAUT: Rect2i(MARGE_PAVE + tiers, base_y, tiers, tiers),
		Bindings.ZONE_GAUCHE: Rect2i(MARGE_PAVE, base_y + tiers, tiers, tiers),
		Bindings.ZONE_DROITE: Rect2i(MARGE_PAVE + 2 * tiers, base_y + tiers, tiers, tiers),
		Bindings.ZONE_BAS: Rect2i(MARGE_PAVE + tiers, base_y + 2 * tiers, tiers, tiers),
	}


# ZONE declaree touchee par un contact, ou chaine vide. L'ordre d'examen est DECLARE :
# pause, dash, puis les quatre directions dans l'ordre fixe.
static func zone_du_contact(position: Vector2i, largeur_fenetre: int, hauteur_fenetre: int) -> String:
	if surface_pause(largeur_fenetre).has_point(position):
		return Bindings.ZONE_PAUSE
	if surface_dash(largeur_fenetre, hauteur_fenetre).has_point(position):
		return Bindings.ZONE_DASH
	var directions: Dictionary = surfaces_directions(hauteur_fenetre)
	for zone in [Bindings.ZONE_HAUT, Bindings.ZONE_GAUCHE, Bindings.ZONE_BAS, Bindings.ZONE_DROITE]:
		if directions[zone].has_point(position):
			return zone
	return ""


# INTENTION portee par un contact : la MEME intention, par le MEME chemin, que le
# clavier et la manette. Un contact hors zone rend AUCUNE.
static func intention_du_contact(position: Vector2i, largeur_fenetre: int, hauteur_fenetre: int) -> int:
	var zone: String = zone_du_contact(position, largeur_fenetre, hauteur_fenetre)
	if zone == "":
		return Intents.Intention.AUCUNE
	return Bindings.intention_de_zone(zone)


# Position du contact portee par un evenement de la plateforme ; (-1, -1) si l'evenement
# n'est pas un appui tactile.
static func position_de_event(event: InputEvent) -> Vector2i:
	if event is InputEventScreenTouch and event.pressed:
		return Vector2i(event.position)
	return Vector2i(-1, -1)


# Les zones declarees sont-elles deux a deux disjointes ? Deux zones qui se recouvrent
# rendraient l'intention d'un contact indecidable.
static func zones_disjointes(largeur_fenetre: int, hauteur_fenetre: int) -> bool:
	var rects: Array = [
		surface_pause(largeur_fenetre),
		surface_dash(largeur_fenetre, hauteur_fenetre),
	]
	var directions: Dictionary = surfaces_directions(hauteur_fenetre)
	for zone in [Bindings.ZONE_HAUT, Bindings.ZONE_GAUCHE, Bindings.ZONE_BAS, Bindings.ZONE_DROITE]:
		rects.append(directions[zone])
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				return false
	return true
