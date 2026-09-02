# v2_touch_pause_surface.gd — ligne touch.pause_surface, capacite F79.
# La SURFACE du bouton de pause est declaree, et un contact sur cette surface se traduit
# en INTENTION DE PAUSE — la meme intention, par le meme chemin, que le clavier et la
# manette.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Touch = preload("res://06_RUNTIME/adapters/touch_input/touch_input.gd")

const LARGEUR: int = 560
const HAUTEUR: int = 720


func run(h) -> void:
	var surface: Rect2i = Touch.surface_pause(LARGEUR)
	h.gt(surface.size.x, 0, "touch.pause: la surface a une largeur declaree")
	h.gt(surface.size.y, 0, "touch.pause: la surface a une hauteur declaree")
	h.eq(surface.end.x <= LARGEUR, true, "touch.pause: la surface tient dans la fenetre")

	# UN CONTACT SUR LA SURFACE produit l'intention de pause.
	var centre: Vector2i = surface.position + surface.size / 2
	h.eq(Touch.zone_du_contact(centre, LARGEUR, HAUTEUR), Bindings.ZONE_PAUSE, "touch.pause: zone reconnue")
	h.eq(Touch.intention_du_contact(centre, LARGEUR, HAUTEUR), Intents.Intention.PAUSE,
		"touch.pause: le contact produit l'intention de pause")

	# HORS SURFACE : aucune intention de pause.
	var loin: Vector2i = Vector2i(LARGEUR / 2, HAUTEUR / 2)
	h.ok(Touch.intention_du_contact(loin, LARGEUR, HAUTEUR) != Intents.Intention.PAUSE,
		"touch.pause: un contact ailleurs ne met pas en pause")
	h.eq(Touch.zone_du_contact(Vector2i(-5, -5), LARGEUR, HAUTEUR), "", "touch.pause: hors fenetre, aucune zone")

	# LE MEME CHEMIN : l'intention ouvre le menu pause, comme les deux autres sources.
	var en_partie: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var r: Dictionary = Shell.appliquer_intention(en_partie, Touch.intention_du_contact(centre, LARGEUR, HAUTEUR))
	h.eq(int(r["session"]["app"]), App.Etat.PAUSE, "touch.pause: le menu pause s'ouvre")

	# LES ZONES sont DEUX A DEUX DISJOINTES : une intention de contact reste decidable.
	h.eq(Touch.zones_disjointes(LARGEUR, HAUTEUR), true, "touch.pause: les zones ne se recouvrent pas")
	var directions: Dictionary = Touch.surfaces_directions(HAUTEUR)
	h.eq(directions.size(), 4, "touch.pause: quatre zones directionnelles declarees")
	h.eq(Touch.intention_du_contact(
		directions[Bindings.ZONE_HAUT].position + directions[Bindings.ZONE_HAUT].size / 2, LARGEUR, HAUTEUR),
		Intents.Intention.HAUT, "touch.pause: la zone haut produit l'intention haut")
