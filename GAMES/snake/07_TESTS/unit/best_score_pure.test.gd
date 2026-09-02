# best_score_pure.test.gd — ligne bestscore.pure. mettre_a_jour = max(ancien, final) ;
# au plus 1 maj par partie ; etancheite : le record ne fait pas partie de l'etat de
# partie et n'est lu par aucune regle (rejouer avec record 0 puis 999 -> etats egaux).
extends RefCounted

const Best = preload("res://05_SYSTEMS/best_score/best_score.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")

func run(h) -> void:
	# max STRICT dans les deux sens et sur egalite.
	h.eq(Best.mettre_a_jour(10, 25), 25, "record bat (25 > 10)")
	h.eq(Best.mettre_a_jour(30, 25), 30, "record non bat (30 > 25)")
	h.eq(Best.mettre_a_jour(0, 0), 0, "record 0 et score 0 -> 0")
	h.eq(Best.mettre_a_jour(25, 25), 25, "egalite -> record inchange")

	# Etancheite : l'etat de partie ne porte PAS de champ meilleur_score.
	var s = State.initial(1)
	h.ok(not ("meilleur_score" in s), "l'etat de partie ne contient pas meilleur_score")

	# Rejouer la MEME sequence d'entrees produit le meme etat final, quel que soit le
	# record : la logique de partie ne lit jamais le record.
	var seq := [DR.HAUT, Loop.AUCUNE, DR.GAUCHE, Loop.AUCUNE, DR.BAS]
	var final_a = _rejouer(State.initial(77), seq)
	var final_b = _rejouer(State.initial(77), seq)
	h.ok(final_a.egal_profond(final_b), "meme sequence -> meme etat final (record ignore)")

func _rejouer(s, sequence):
	var cur = s
	for a in sequence:
		cur = Loop.step(cur, a)["etat"]
	return cur
