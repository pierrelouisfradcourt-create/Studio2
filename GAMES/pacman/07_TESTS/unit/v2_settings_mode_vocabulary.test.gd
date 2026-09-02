# v2_settings_mode_vocabulary.test.gd — ligne settings.mode_vocabulary, capacite F81.
# Le mode expose appartient a l'ensemble des DEUX valeurs A CHAQUE RELEVE, jamais vide
# ni double. Modele PUR : en drapeau de runtime, ni l'exclusivite ni le defaut ne
# seraient mesurables.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	h.eq(Reglages.MODES_VALIDES.size(), 2, "settings.vocab: deux modes declares")
	h.eq(Reglages.valide(Reglages.Mode.NORMAL), true, "settings.vocab: mode normal valide")
	h.eq(Reglages.valide(Reglages.Mode.TEST), true, "settings.vocab: mode test valide")
	h.eq(Reglages.valide(2), false, "settings.vocab: une troisieme valeur est refusee")
	h.eq(Reglages.valide(-1), false, "settings.vocab: une valeur negative est refusee")
	h.eq(Reglages.nom(Reglages.Mode.NORMAL), "NORMAL", "settings.vocab: nom du mode normal")
	h.eq(Reglages.nom(Reglages.Mode.TEST), "TEST", "settings.vocab: nom du mode test")
	h.eq(Reglages.nom(9), "", "settings.vocab: un mode inconnu n'a pas de nom")

	# MUTUELLEMENT EXCLUSIFS ET EXHAUSTIFS : la bascule mene a l'AUTRE, jamais ailleurs.
	h.eq(Reglages.mode_suivant(Reglages.Mode.NORMAL), Reglages.Mode.TEST, "settings.vocab: bascule vers test")
	h.eq(Reglages.mode_suivant(Reglages.Mode.TEST), Reglages.Mode.NORMAL, "settings.vocab: bascule vers normal")
	h.eq(Reglages.mode_suivant(Reglages.mode_suivant(Reglages.Mode.NORMAL)), Reglages.Mode.NORMAL,
		"settings.vocab: deux bascules reviennent au depart")

	# A CHAQUE RELEVE : le mode expose reste dans l'ensemble des deux valeurs.
	var jeu = State.initial(Maze, 9)
	var hors_vocabulaire: int = 0
	var vides: int = 0
	for _t in range(30):
		jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
		var nom: String = Observable.projeter(jeu)["mode_jeu"]
		if nom == "":
			vides += 1
		if nom != "NORMAL" and nom != "TEST":
			hors_vocabulaire += 1
	h.eq(hors_vocabulaire, 0, "settings.vocab: 0 releve hors vocabulaire sur 30 ticks")
	h.eq(vides, 0, "settings.vocab: 0 releve vide sur 30 ticks")

	# NORMALISATION : une valeur hors vocabulaire retombe sur le defaut declare.
	h.eq(Reglages.normaliser({"mode": 7})["mode"], Reglages.MODE_PAR_DEFAUT,
		"settings.vocab: une valeur hors vocabulaire retombe sur le defaut")
	h.eq(Reglages.avec_mode({}, Reglages.Mode.TEST)["mode"], Reglages.Mode.TEST,
		"settings.vocab: le mode declare est retenu")
	h.eq(Reglages.avec_mode({}, 7)["mode"], Reglages.MODE_PAR_DEFAUT,
		"settings.vocab: un mode invalide ne s'installe pas")
