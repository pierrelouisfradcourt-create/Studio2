# no_reverse.test.gd — ligne core.direction_rules. Le refus se compare a la DERNIERE
# DIRECTION EFFECTUEE, jamais a une direction en attente. N appuis -> 1 seul changement
# (dernier appui legal). Un demi-tour est ignore, pas mis en file, jamais rejoue.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")

func run(h) -> void:
	# Fixture de la carte : direction effectuee = HAUT ; appuis DROITE, HAUT, GAUCHE
	# dans le meme intervalle. Aucun n'est le demi-tour de HAUT (dont l'oppose est BAS).
	var s = State.initial(1)
	s.dir_effectuee = DR.HAUT
	s.dir_en_attente = DR.HAUT
	h.eq(DR.demander(s, DR.DROITE), true, "appui DROITE accepte")
	h.eq(DR.demander(s, DR.HAUT), true, "appui HAUT accepte")
	h.eq(DR.demander(s, DR.GAUCHE), true, "appui GAUCHE accepte")
	# Le dernier appui legal l'emporte (profondeur 1, ecrasement).
	h.eq(DR.direction_du_tick(s), DR.GAUCHE, "direction du tick = dernier appui legal (GAUCHE)")

	# Demi-tour : serpent vers la DROITE, appui GAUCHE (oppose) -> ignore, continue tout droit.
	var s2 = State.initial(1)
	s2.dir_effectuee = DR.DROITE
	s2.dir_en_attente = DR.DROITE
	h.eq(DR.demander(s2, DR.GAUCHE), false, "demi-tour GAUCHE refuse (vs DROITE effectuee)")
	h.eq(s2.dir_en_attente, DR.DROITE, "direction en attente inchangee apres demi-tour")
	h.eq(DR.direction_du_tick(s2), DR.DROITE, "le serpent continue tout droit")

	# Comparaison a la direction EFFECTUEE, pas a une direction en attente :
	# effectuee=DROITE, on met HAUT en attente, PUIS on demande GAUCHE. GAUCHE est le
	# demi-tour de DROITE (effectuee) -> refuse, meme si l'attente est HAUT.
	var s3 = State.initial(1)
	s3.dir_effectuee = DR.DROITE
	s3.dir_en_attente = DR.DROITE
	h.eq(DR.demander(s3, DR.HAUT), true, "HAUT accepte (perpendiculaire a DROITE)")
	h.eq(DR.demander(s3, DR.GAUCHE), false, "GAUCHE refuse : demi-tour de l'EFFECTUEE, pas de l'attente")
	h.eq(s3.dir_en_attente, DR.HAUT, "l'attente reste HAUT")

	# Un demi-tour n'est jamais rejoue : apres un tick, l'etat n'a pas garde la commande.
	var s4 = State.initial(1)
	s4.dir_effectuee = DR.DROITE
	s4.dir_en_attente = DR.DROITE
	DR.demander(s4, DR.GAUCHE)  # ignore
	var r = Loop.step(s4, Loop.AUCUNE)
	h.eq(r["etat"].dir_effectuee, DR.DROITE, "apres tick, toujours DROITE (demi-tour non rejoue)")
	h.ok(r["etat"].statut == State.Statut.EN_COURS, "toujours en cours (pas de mort par demi-tour)")

	# Direction HORS vocabulaire ferme (diagonale, vecteur nul) : refusee, attente intacte.
	var sv = State.initial(1)
	sv.dir_effectuee = DR.HAUT
	sv.dir_en_attente = DR.HAUT
	h.eq(DR.demander(sv, Vector2i(1, 1)), false, "diagonale refusee (hors vocabulaire)")
	h.eq(sv.dir_en_attente, DR.HAUT, "attente inchangee apres direction invalide")
	h.eq(DR.demander(sv, Vector2i(0, 0)), false, "vecteur nul refuse")

	# N appuis (N>=2) legaux -> EXACTEMENT 1 changement de direction (le dernier).
	var s5 = State.initial(1)
	s5.dir_effectuee = DR.HAUT
	s5.dir_en_attente = DR.HAUT
	for d in [DR.DROITE, DR.GAUCHE, DR.DROITE, DR.GAUCHE]:
		DR.demander(s5, d)
	h.eq(DR.direction_du_tick(s5), DR.GAUCHE, "rafale -> 1 changement, dernier legal (GAUCHE)")
