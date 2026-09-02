# v2_touch_no_logic_touch.gd — ligne touch.no_logic_touch, capacite F80.
# Le tactile est une SOURCE D'INTENTIONS DE PLUS : son ajout n'ouvre aucun chemin de
# pause parallele, n'introduit aucune notion de doigt ni d'ecran dans la logique, et ne
# touche AUCUN fichier de 05_SYSTEMS.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Touch = preload("res://06_RUNTIME/adapters/touch_input/touch_input.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	# AUCUNE NOTION DE TACTILE dans la logique.
	var fautifs: Array = Purity.fichiers_portant("res://05_SYSTEMS",
		["InputEventScreenTouch", "Rect2i", "surface_pause", "ZONE_", "touch_input"])
	h.eq(fautifs.size(), 0, "touch.no_logic: 0 fichier de logique ne connait le tactile")
	# CONTROLE POSITIF : ces memes notions existent bien dans le runtime.
	var lecteurs: Array = Purity.fichiers_portant("res://06_RUNTIME", ["InputEventScreenTouch"])
	h.gt(lecteurs.size(), 0, "touch.no_logic: le tactile existe du cote runtime")

	# AUCUN CHEMIN DE PAUSE PARALLELE : le tactile emprunte la transition unique.
	var f := FileAccess.open("res://06_RUNTIME/adapters/touch_input/touch_input.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("App.Etat"), false, "touch.no_logic: le tactile ne decide d'aucun etat")
	h.eq(texte.contains("vers_pause"), false, "touch.no_logic: il n'appelle aucune transition lui-meme")
	h.eq(texte.contains("Bindings."), true, "touch.no_logic: il passe par la table de liaisons")

	# IL PRODUIT DES INTENTIONS, et rien d'autre.
	var zone_pause: int = Touch.intention_du_contact(
		Touch.surface_pause(560).position + Vector2i(2, 2), 560, 720)
	h.eq(Intents.valide(zone_pause), true, "touch.no_logic: la sortie est une intention du vocabulaire ferme")
	h.eq(zone_pause, Intents.Intention.PAUSE, "touch.no_logic: et c'est l'intention de pause")
	h.eq(Touch.position_de_event(InputEventKey.new()), Vector2i(-1, -1),
		"touch.no_logic: un evenement non tactile ne produit aucune position")

	# LE MEME VOCABULAIRE que les deux autres peripheriques : aucune intention propre.
	var propres: int = 0
	for zone in [Bindings.ZONE_HAUT, Bindings.ZONE_GAUCHE, Bindings.ZONE_BAS, Bindings.ZONE_DROITE,
			Bindings.ZONE_DASH, Bindings.ZONE_PAUSE]:
		var i: int = Bindings.intention_de_zone(zone)
		if not Intents.TOUTES.has(i):
			propres += 1
	h.eq(propres, 0, "touch.no_logic: aucune intention propre au tactile")
