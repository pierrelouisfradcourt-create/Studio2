# end_conditions_strict.test.gd — ligne end.strict_conditions. Assertions par EGALITE STRICTE
# (aucune tautologie >=/<=) : GAGNE ssi briques == 0 ; PERDU ssi vies == 0 ; les 3 statuts
# exclusifs et exhaustifs. Reciproques comptees a EXACTEMENT 0.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const End = preload("res://05_SYSTEMS/game_state/end_condition.gd")

func run(h) -> void:
	# --- predicats stricts ---
	h.eq(End.est_gagne(0), true, "est_gagne(0) vrai")
	h.eq(End.est_gagne(1), false, "est_gagne(1) faux")
	h.eq(End.est_gagne(60), false, "est_gagne(60) faux")
	h.eq(End.est_perdu(0), true, "est_perdu(0) vrai")
	h.eq(End.est_perdu(1), false, "est_perdu(1) faux")
	h.eq(End.est_perdu(3), false, "est_perdu(3) faux")

	# --- appliquer : VICTOIRE ssi 0 brique ---
	var g = State.initial(1)
	g.briques_restantes = 0
	End.appliquer(g)
	h.eq(g.statut, State.Statut.GAGNE, "0 brique -> GAGNE")

	# etat GAGNE avec briques != 0 : impossible via appliquer (reciproque = 0)
	var gg = State.initial(1)
	gg.briques_restantes = 5
	End.appliquer(gg)
	h.eq(gg.statut != State.Statut.GAGNE, true, "briques != 0 -> jamais GAGNE")

	# --- appliquer : DEFAITE ssi 0 vie (et encore des briques) ---
	var p = State.initial(1)
	p.vies = 0
	End.appliquer(p)
	h.eq(p.statut, State.Statut.PERDU, "0 vie -> PERDU")

	var pp = State.initial(1)
	pp.vies = 2
	End.appliquer(pp)
	h.eq(pp.statut != State.Statut.PERDU, true, "vies != 0 -> jamais PERDU")

	# --- exclusivite : la victoire prime si 0 brique ET 0 vie ---
	var x = State.initial(1)
	x.briques_restantes = 0
	x.vies = 0
	End.appliquer(x)
	h.eq(x.statut, State.Statut.GAGNE, "0 brique ET 0 vie -> GAGNE prime (exclusif)")

	# --- exhaustivite : hors des deux conditions, reste EN_COURS ---
	var e = State.initial(1)
	End.appliquer(e)
	h.eq(e.statut, State.Statut.EN_COURS, "ni 0 brique ni 0 vie -> EN_COURS")

	# --- appliquer sur un etat deja terminal ne le change pas ---
	var t = State.initial(1)
	t.statut = State.Statut.GAGNE
	t.briques_restantes = 10
	t.vies = 0
	End.appliquer(t)
	h.eq(t.statut, State.Statut.GAGNE, "statut terminal fige (pas de re-decision)")

	# --- balayage : sur un echantillon d'etats, jamais 0 ni 2 statuts vrais ---
	var double_ou_zero := 0
	for br in [0, 3, 60]:
		for vi in [0, 1, 3]:
			var s = State.initial(1)
			s.briques_restantes = br
			s.vies = vi
			End.appliquer(s)
			var n := 0
			if s.statut == State.Statut.EN_COURS: n += 1
			if s.statut == State.Statut.GAGNE: n += 1
			if s.statut == State.Statut.PERDU: n += 1
			if n != 1:
				double_ou_zero += 1
	h.eq(double_ou_zero, 0, "chaque etat porte EXACTEMENT 1 statut (0 double, 0 vide)")
