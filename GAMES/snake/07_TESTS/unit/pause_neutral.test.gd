# pause_neutral.test.gd — ligne pause.state. Pendant la pause : 0 tick, 0 mutation ;
# l'etat avant pause et apres reprise sont PROFONDEMENT EGAUX (sauf l'indicateur de
# pause) ; EXACTEMENT 1 tick applique a la premiere trame de reprise.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Pause = preload("res://05_SYSTEMS/game_state/pause.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

func run(h) -> void:
	var s = State.initial(9)
	# Avance quelques ticks pour avoir un etat non trivial.
	for i in range(3):
		s = Loop.step(s, Loop.AUCUNE)["etat"]
	var avant = s.clone()

	# Mise en pause : seul le statut change.
	Pause.basculer(s)
	h.eq(s.statut, State.Statut.EN_PAUSE, "statut = en pause apres bascule")

	# Pendant la pause, N tentatives de tick (avec entrees) ne changent RIEN.
	for i in range(100):
		s = Loop.step(s, DR.HAUT)["etat"]
	h.eq(s.ticks, avant.ticks, "0 tick applique pendant la pause")
	# Egalite profonde sur TOUS les champs sauf le statut.
	var champs_ok: bool = (s.segments == avant.segments
		and s.dir_effectuee == avant.dir_effectuee
		and s.dir_en_attente == avant.dir_en_attente
		and s.nourriture == avant.nourriture
		and s.score == avant.score
		and s.longueur == avant.longueur
		and s.periode == avant.periode
		and s.fruits == avant.fruits
		and s.palier == avant.palier
		and s.ticks == avant.ticks
		and s.rng_state == avant.rng_state)
	h.ok(champs_ok, "etat inchange pendant la pause (sauf statut)")

	# Reprise : le statut redevient en cours, et exactement 1 tick s'applique.
	Pause.basculer(s)
	h.eq(s.statut, State.Statut.EN_COURS, "statut = en cours apres reprise")
	h.ok(s.egal_profond(avant), "etat de reprise profondement egal a l'etat d'avant pause")
	var apres_reprise = Loop.step(s, Loop.AUCUNE)["etat"]
	h.eq(apres_reprise.ticks, avant.ticks + 1, "exactement 1 tick a la premiere trame de reprise")
