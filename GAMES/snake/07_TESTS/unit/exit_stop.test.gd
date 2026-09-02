# exit_stop.test.gd — ligne runtime.exit_observable (+ core.exit). Le code de sortie est
# EXACTEMENT 0 ; et CHAQUE commande exposee (direction, pause, reprise, relance, sortie)
# produit un changement LISIBLE dans l'etat expose (via le meme canal public que le clavier).
# Assertions STRICTES.
extends RefCounted

const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const IA = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Pause = preload("res://05_SYSTEMS/game_state/pause.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

func run(h) -> void:
	# Sortie : code EXACTEMENT 0, commande reconnue, autres commandes non confondues.
	h.eq(Exit.CODE_SORTIE, 0, "code de sortie = 0")
	h.ok(Exit.est_sortie(IA.CMD_SORTIE), "commande sortie reconnue")
	h.ok(not Exit.est_sortie(IA.CMD_PAUSE), "pause n'est pas sortie")
	# Chaque commande exposee a une etiquette d'effet observable NON VIDE et correcte.
	h.eq(Exit.etiquette_effet(IA.traduire_keycode(KEY_UP)), "direction_demandee", "direction -> effet")
	h.eq(Exit.etiquette_effet(IA.traduire_keycode(KEY_P)), "bascule_pause", "pause -> effet")
	h.eq(Exit.etiquette_effet(IA.traduire_keycode(KEY_R)), "etat_reinitialise", "relance -> effet")
	h.eq(Exit.etiquette_effet(IA.traduire_keycode(KEY_ESCAPE)), "processus_termine", "sortie -> effet")
	# Effets observables REELS via les systemes purs (canal public).
	var s = State.initial(3)
	Pause.basculer(s)
	h.eq(s.statut, State.Statut.EN_PAUSE, "pause : statut observable EN_PAUSE")
	Pause.basculer(s)
	h.eq(s.statut, State.Statut.EN_COURS, "reprise : statut observable EN_COURS")
	var s2 = State.initial(3)
	s2.ticks = 12
	var relance = Restart.relancer(3)
	h.eq(relance.ticks, 0, "relance : ticks observable remis a 0")
	var s3 = State.initial(3)
	# Serpent vertical vers HAUT pour qu'un virage GAUCHE soit legal (non demi-tour).
	s3.segments = [Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12)]
	s3.dir_effectuee = DR.HAUT
	s3.dir_en_attente = DR.HAUT
	DR.demander(s3, DR.GAUCHE)
	h.eq(s3.dir_en_attente, DR.GAUCHE, "direction : dir_en_attente observable changee")
