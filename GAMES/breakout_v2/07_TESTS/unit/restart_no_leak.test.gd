# restart_no_leak.test.gd — ligne runtime.restart_one_gesture. Apres une partie avancee, la
# relance produit un etat STRICTEMENT identique au premier demarrage (0 residu).
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var initial = State.initial(P.SEED_REFERENCE)

	# Simuler une partie AVANCEE (etat pollue de residus).
	var s = State.initial(P.SEED_REFERENCE)
	BrickField.detruire(s, 0)
	BrickField.detruire(s, 1)
	s.score = 20
	s.vies = 1
	s.ticks = 500
	s.paddle_x = P.raquette_demi_largeur()
	s.statut = State.Statut.PERDU

	# Relance a meme graine -> etat neuf.
	var neuf = Restart.relancer(P.SEED_REFERENCE)
	h.ok(neuf.egal_profond(initial), "relance -> etat STRICTEMENT identique au 1er demarrage (0 residu)")
	h.eq(neuf.score, 0, "score remis a 0")
	h.eq(neuf.ticks, 0, "ticks remis a 0")
	h.eq(neuf.vies, P.VIES_INITIALES, "vies remises au maximum")
	h.eq(neuf.briques_restantes, P.total_briques(), "toutes les briques revenues")
	h.eq(neuf.statut, State.Statut.EN_COURS, "statut EN_COURS apres relance")
	h.eq(neuf.paddle_x, P.TERRAIN_LARGEUR / 2.0, "raquette recentree")

	# L'etat AVANCE, lui, differait bien de l'initial (controle : le test n'est pas trivial).
	h.eq(s.egal_profond(initial), false, "controle : l'etat avance differait de l'initial")
