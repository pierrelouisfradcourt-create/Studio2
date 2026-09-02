# core_input_action.gd — oracle de la ligne core.input. SceneTree headless : une action
# emise sur le canal d'entree PUBLIC (le meme pour clavier et bot) modifie l'etat de facon
# OBSERVABLE. Verifie que chaque direction legale change la trajectoire au tick suivant.
# Sortie : "FORGE_ORACLE core_input_action {json}", exit 0 si vert.
extends SceneTree

const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

func _initialize() -> void:
	var fails: Array = []
	# Serpent vertical vers HAUT : un virage GAUCHE puis DROITE (perpendiculaires) est legal.
	for touche in [KEY_LEFT, KEY_RIGHT]:
		var s = State.initial(4)
		s.segments = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
		s.longueur = 3
		s.dir_effectuee = DR.HAUT
		s.dir_en_attente = DR.HAUT
		s.nourriture = Vector2i(19, 19)
		var action = IA.traduire_keycode(touche)
		var attendu: Vector2i = s.segments[0] + action["dir"]
		# Canal public unique : l'action passe par le MEME step() que le clavier.
		var apres = Loop.step(s, action["dir"])["etat"]
		if apres.segments[0] != attendu:
			fails.append("touche %d : tete non deplacee comme demande" % touche)
	# Une touche non liee ne modifie pas la trajectoire (reste tout droit).
	var s2 = State.initial(4)
	s2.segments = [Vector2i(10, 10), Vector2i(9, 10), Vector2i(8, 10)]
	s2.longueur = 3
	s2.dir_effectuee = DR.DROITE
	s2.dir_en_attente = DR.DROITE
	s2.nourriture = Vector2i(19, 19)
	var inerte = IA.traduire_keycode(KEY_J)
	if inerte["kind"] != "aucun":
		fails.append("touche non liee produit une action")
	print("FORGE_ORACLE core_input_action " + JSON.stringify({"ok": fails.is_empty(), "fails": fails}))
	quit(0 if fails.is_empty() else 1)
