# state_status.test.gd — ligne core.game_state. Statut EXACTEMENT une valeur parmi 3, etat
# initial valide et reconstructible, egalite profonde sensible a chaque champ.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var s = State.initial(12345)
	h.eq(s.statut, State.Statut.EN_COURS, "statut initial = EN_COURS")
	h.ok(s.statut in State.STATUTS_VALIDES, "statut dans les 3 valeurs")
	h.eq(State.STATUTS_VALIDES.size(), 3, "exactement 3 statuts declares")
	h.ok(s.est_valide(), "etat initial structurellement valide")
	h.eq(s.briques_restantes, P.total_briques(), "briques initiales = rangees*colonnes")
	h.eq(s.vies, P.VIES_INITIALES, "vies initiales = VIES_INITIALES")
	h.eq(s.score, 0, "score initial 0")
	h.eq(s.ticks, 0, "ticks initial 0")
	h.eq(s.paddle_x, P.TERRAIN_LARGEUR / 2.0, "raquette centree au demarrage")
	# Lecture sans effet de bord : deux projections consecutives identiques.
	h.ok(s.egal_profond(s.clone()), "clone profondement egal a l'original")
	# Determinisme : meme graine -> etat identique.
	var s2 = State.initial(12345)
	h.ok(s.egal_profond(s2), "meme graine -> etat identique (deterministe)")

	# --- est_valide : cas NEGATIFS (le validateur DOIT renvoyer false) ---
	var v = State.initial(1)
	h.ok(v.est_valide(), "base valide (controle)")
	var b1 = v.clone(); b1.statut = 99
	h.eq(b1.est_valide(), false, "statut hors enum -> invalide")
	var b2 = v.clone(); b2.vies = -1
	h.eq(b2.est_valide(), false, "vies negatives -> invalide")
	var b3 = v.clone(); b3.briques_restantes = v.briques_restantes - 1
	h.eq(b3.est_valide(), false, "compte restant != briques presentes -> invalide")
	var b4 = v.clone(); b4.paddle_x = -1.0
	h.eq(b4.est_valide(), false, "raquette hors borne gauche -> invalide")
	var b5 = v.clone(); b5.paddle_x = P.TERRAIN_LARGEUR + 1.0
	h.eq(b5.est_valide(), false, "raquette hors borne droite -> invalide")
	# DURCISSEMENT MUTATION — est_valide renvoie bien false sur CHAQUE cas negatif restant :
	var b6 = v.clone(); b6.briques_restantes = -1
	h.eq(b6.est_valide(), false, "briques_restantes negatif -> invalide (return false)")
	var b7 = v.clone()
	b7.bricks = []
	for _i in range(P.total_briques() - 1):   # tableau plus court que la grille
		b7.bricks.append(true)
	b7.briques_restantes = b7.bricks.size()   # compte coherent avec compter_briques (passe la borne precedente)
	h.eq(b7.est_valide(), false, "taille du tableau de briques != grille -> invalide (return false)")

	# --- egal_profond : SENSIBLE a CHAQUE champ ---
	var e = State.initial(1)
	var c1 = e.clone(); c1.score = e.score + 1
	h.eq(e.egal_profond(c1), false, "egal_profond faux si score differe")
	var c2 = e.clone(); c2.ticks = e.ticks + 1
	h.eq(e.egal_profond(c2), false, "egal_profond faux si ticks differe")
	var c3 = e.clone(); c3.vies = e.vies + 1
	h.eq(e.egal_profond(c3), false, "egal_profond faux si vies differe")
	var c4 = e.clone(); c4.ball_pos = e.ball_pos + Vector2(1.0, 0.0)
	h.eq(e.egal_profond(c4), false, "egal_profond faux si ball_pos differe")
	var c5 = e.clone(); c5.ball_vel = e.ball_vel + Vector2(0.0, 1.0)
	h.eq(e.egal_profond(c5), false, "egal_profond faux si ball_vel differe")
	var c6 = e.clone(); c6.paddle_x = e.paddle_x + 1.0
	h.eq(e.egal_profond(c6), false, "egal_profond faux si paddle_x differe")
	var c7 = e.clone(); c7.briques_restantes = e.briques_restantes - 1
	h.eq(e.egal_profond(c7), false, "egal_profond faux si briques_restantes differe")
	var c8 = e.clone(); c8.start_y = e.start_y + 1.0
	h.eq(e.egal_profond(c8), false, "egal_profond faux si start_y differe")
	var c9 = e.clone(); c9.statut = State.Statut.PERDU
	h.eq(e.egal_profond(c9), false, "egal_profond faux si statut differe")
	var c10 = e.clone(); c10.seed = e.seed + 1
	h.eq(e.egal_profond(c10), false, "egal_profond faux si seed differe")
	var c11 = e.clone(); c11.niveau = e.niveau + 1
	h.eq(e.egal_profond(c11), false, "egal_profond faux si niveau differe")
	var c12 = e.clone(); c12.bricks = e.bricks.duplicate(); c12.bricks[0] = false
	h.eq(e.egal_profond(c12), false, "egal_profond faux si bricks differe")
