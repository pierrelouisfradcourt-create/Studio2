# error_guard_invalid_input.test.gd — ligne core.error_handling. Sur les entrees hors
# domaine (action nulle, direction hors vocabulaire, demi-tour, deux directions au meme
# tick, rafale), l'etat reste STRUCTURELLEMENT VALIDE : 0 etat invalide, 0 exception.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

func run(h) -> void:
	var invalides := 0

	# Action nulle : le serpent avance, etat valide.
	var s = State.initial(21)
	var r = Loop.step(s, Loop.AUCUNE)["etat"]
	if not r.est_valide():
		invalides += 1
	h.ok(r.est_valide(), "action nulle -> etat valide")

	# Direction hors vocabulaire (diagonale) : ignoree, etat valide.
	var s2 = State.initial(21)
	var r2 = Loop.step(s2, Vector2i(1, 1))["etat"]
	if not r2.est_valide():
		invalides += 1
	h.ok(r2.est_valide(), "direction diagonale ignoree -> etat valide")
	h.ok(DR.est_direction(Vector2i(1, 1)) == false, "diagonale hors vocabulaire ferme")

	# Demi-tour direct : ignore, serpent vivant et valide.
	var s3 = State.initial(21)
	s3.dir_effectuee = DR.DROITE
	s3.dir_en_attente = DR.DROITE
	var r3 = Loop.step(s3, DR.GAUCHE)["etat"]
	if not r3.est_valide():
		invalides += 1
	h.eq(r3.statut, State.Statut.EN_COURS, "demi-tour ignore -> serpent vivant")

	# Deux directions au meme intervalle puis tick : dernier legal, etat valide.
	var s4 = State.initial(21)
	s4.dir_effectuee = DR.HAUT
	s4.dir_en_attente = DR.HAUT
	DR.demander(s4, DR.DROITE)
	DR.demander(s4, DR.GAUCHE)
	var r4 = Loop.step(s4, Loop.AUCUNE)["etat"]
	if not r4.est_valide():
		invalides += 1
	h.ok(r4.est_valide(), "deux directions au meme tick -> etat valide")

	# Rafale de 50 entrees quelconques : jamais d'etat invalide.
	var s5 = State.initial(21)
	var entrees := [DR.HAUT, DR.BAS, DR.GAUCHE, DR.DROITE, Vector2i(9, 9), Loop.AUCUNE]
	for i in range(50):
		s5 = Loop.step(s5, entrees[i % entrees.size()])["etat"]
		if not s5.est_valide():
			invalides += 1
	h.ok(s5.est_valide() or s5.statut == State.Statut.TERMINE_PERDU, "rafale -> etat valide ou mort propre")

	# Bilan : EXACTEMENT 0 etat invalide produit.
	h.eq(invalides, 0, "0 etat structurellement invalide sur toutes les entrees hors domaine")
