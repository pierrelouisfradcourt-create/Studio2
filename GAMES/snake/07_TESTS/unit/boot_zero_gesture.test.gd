# boot_zero_gesture.test.gd — ligne runtime.boot_immediate (+ core.boot). Le nombre
# d'appuis avant que le serpent avance est EXACTEMENT 0 et aucun ecran de menu/chargement
# n'est intercale : l'etat initial declare est atteint des le boot et avance au premier tick
# sans aucun geste. Assertions STRICTES.
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	h.eq(Boot.GESTES_AVANT_DEMARRAGE, 0, "0 geste avant demarrage")
	h.eq(Boot.ECRANS_INTERCALES, 0, "0 ecran intercale")
	var s = Boot.etat_initial(7)
	h.eq(s.statut, State.Statut.EN_COURS, "boot : statut EN_COURS immediat")
	h.eq(s.longueur, P.LONGUEUR_INITIALE, "boot : longueur initiale declaree")
	# Sans AUCUNE entree, le serpent avance au premier tick (pret des le boot).
	var tete_avant = s.segments[0]
	var apres = Loop.step(s, Loop.AUCUNE)["etat"]
	h.eq(apres.segments[0], tete_avant + DR.DROITE, "avance au 1er tick sans geste (vers DROITE)")
