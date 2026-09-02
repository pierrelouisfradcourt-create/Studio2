# state_status.test.gd — ligne core.game_state. A tout instant le statut vaut EXACTEMENT
# une valeur parmi les 4 ; l'etat initial est structurellement valide et reconstructible.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var s = State.initial(12345)
	# Statut initial = EN_COURS, et c'est EXACTEMENT une des 4 valeurs.
	h.eq(s.statut, State.Statut.EN_COURS, "statut initial = EN_COURS")
	h.ok(s.statut in State.STATUTS_VALIDES, "statut appartient aux 4 valeurs")
	h.eq(State.STATUTS_VALIDES.size(), 4, "exactement 4 statuts declares")
	# Etat initial structurellement valide.
	h.ok(s.est_valide(), "etat initial structurellement valide")
	# Longueur == nombre de segments == longueur initiale.
	h.eq(s.segments.size(), P.LONGUEUR_INITIALE, "segments = longueur initiale")
	h.eq(s.longueur, P.LONGUEUR_INITIALE, "champ longueur = longueur initiale")
	# Compteurs a zero, periode initiale.
	h.eq(s.score, 0, "score initial 0")
	h.eq(s.fruits, 0, "fruits initial 0")
	h.eq(s.palier, 0, "palier initial 0")
	h.eq(s.ticks, 0, "ticks initial 0")
	h.eq(s.periode, P.VITESSE_INITIALE_MS, "periode initiale = vitesse initiale")
	# La nourriture initiale n'est pas sous le corps.
	h.ok(not (s.nourriture in s.segments), "nourriture initiale hors du corps")
	# Reconstruction deterministe : meme graine -> etat profondement egal.
	var s2 = State.initial(12345)
	h.ok(s.egal_profond(s2), "meme graine -> etat identique (deterministe)")
	# Graine differente -> nourriture potentiellement differente, mais toujours valide.
	var s3 = State.initial(999)
	h.ok(s3.est_valide(), "autre graine -> etat valide")

	# --- est_valide : cas NEGATIFS (le validateur DOIT renvoyer false) ---
	var v = State.initial(1)
	h.ok(v.est_valide(), "base valide (controle)")
	var b1 = v.clone(); b1.statut = 99
	h.eq(b1.est_valide(), false, "statut hors enum -> invalide")
	var b2 = v.clone(); b2.longueur = v.longueur + 1
	h.eq(b2.est_valide(), false, "longueur != nombre de segments -> invalide")
	var b3 = v.clone(); b3.segments[0] = Vector2i(P.TAILLE_GRILLE, 5)
	h.eq(b3.est_valide(), false, "segment x = taille -> invalide (borne haute STRICTE)")
	var b4 = v.clone(); b4.segments[0] = Vector2i(-1, 5)
	h.eq(b4.est_valide(), false, "segment x = -1 -> invalide")
	var b5 = v.clone(); b5.segments[0] = Vector2i(5, P.TAILLE_GRILLE)
	h.eq(b5.est_valide(), false, "segment y = taille -> invalide")
	var b6 = v.clone(); b6.segments[0] = Vector2i(5, -1)
	h.eq(b6.est_valide(), false, "segment y = -1 -> invalide")
	var b7 = v.clone(); b7.nourriture = Vector2i(P.TAILLE_GRILLE, 0)
	h.eq(b7.est_valide(), false, "nourriture x = taille -> invalide")
	var b8 = v.clone(); b8.nourriture = Vector2i(-1, 0)
	h.eq(b8.est_valide(), false, "nourriture x = -1 -> invalide")
	var b9 = v.clone(); b9.nourriture = v.segments[0]
	h.eq(b9.est_valide(), false, "nourriture sur le corps -> invalide")
	# Bornes en Y de la nourriture (symetrie stricte avec X : ferme les mutants ge->gt /
	# or->and de state.gd:88 que seul le cote X couvrait).
	var b10 = v.clone(); b10.nourriture = Vector2i(0, P.TAILLE_GRILLE)
	h.eq(b10.est_valide(), false, "nourriture y = taille -> invalide (borne haute STRICTE)")
	var b11 = v.clone(); b11.nourriture = Vector2i(0, -1)
	h.eq(b11.est_valide(), false, "nourriture y = -1 -> invalide")

	# --- egal_profond : SENSIBLE a CHAQUE champ (false si un seul champ differe) ---
	var e = State.initial(1)
	var c1 = e.clone(); c1.score = e.score + 1
	h.eq(e.egal_profond(c1), false, "egal_profond faux si score differe")
	var c2 = e.clone(); c2.ticks = e.ticks + 1
	h.eq(e.egal_profond(c2), false, "egal_profond faux si ticks differe")
	var c3 = e.clone(); c3.longueur = e.longueur + 1
	h.eq(e.egal_profond(c3), false, "egal_profond faux si longueur differe")
	var c4 = e.clone(); c4.periode = e.periode + 1.0
	h.eq(e.egal_profond(c4), false, "egal_profond faux si periode differe")
	var c5 = e.clone(); c5.fruits = e.fruits + 1
	h.eq(e.egal_profond(c5), false, "egal_profond faux si fruits differe")
	var c6 = e.clone(); c6.palier = e.palier + 1
	h.eq(e.egal_profond(c6), false, "egal_profond faux si palier differe")
	var c7 = e.clone(); c7.rng_state = e.rng_state + 1
	h.eq(e.egal_profond(c7), false, "egal_profond faux si rng_state differe")
	var c8 = e.clone(); c8.nourriture = e.nourriture + Vector2i(1, 0)
	h.eq(e.egal_profond(c8), false, "egal_profond faux si nourriture differe")
	var c9 = e.clone(); c9.segments[0] = e.segments[0] + Vector2i(0, 1)
	h.eq(e.egal_profond(c9), false, "egal_profond faux si segments differe")
	var c10 = e.clone(); c10.dir_effectuee = Vector2i(0, -1)
	h.eq(e.egal_profond(c10), false, "egal_profond faux si dir_effectuee differe")
	var c11 = e.clone(); c11.dir_en_attente = Vector2i(0, -1)
	h.eq(e.egal_profond(c11), false, "egal_profond faux si dir_en_attente differe")
