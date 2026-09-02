# event_observer.test.gd — ligne loop.event_socket. Vocabulaire FERME d'evenements-donnees
# (5 types), constructeurs corrects, et emission REELLE lors d'un tick qui casse une brique.
extends RefCounted

const Events = preload("res://05_SYSTEMS/game_loop/events.gd")
const Wall = preload("res://05_SYSTEMS/wall_collision/wall_reflection.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")

func run(h) -> void:
	# --- vocabulaire ferme : 5 types ---
	h.eq(Events.VOCABULAIRE.size(), 5, "5 types d'evenements")

	# --- constructeurs : type + charge utile corrects ---
	h.eq(Events.brique_detruite(3)["type"], Events.BRIQUE_DETRUITE, "brique_detruite: type")
	h.eq(Events.brique_detruite(3)["index"], 3, "brique_detruite: index")
	h.eq(Events.rebond_mur(Wall.GAUCHE)["type"], Events.REBOND_MUR, "rebond_mur: type")
	h.eq(Events.rebond_mur(Wall.GAUCHE)["face"], Wall.GAUCHE, "rebond_mur: face")
	h.eq(Events.rebond_raquette(0.5)["offset"], 0.5, "rebond_raquette: offset")
	h.eq(Events.vie_perdue(2)["vies"], 2, "vie_perdue: vies restantes")
	h.eq(Events.fin_partie(State.Statut.GAGNE)["statut"], State.Statut.GAGNE, "fin_partie: statut")

	# --- emission REELLE : un tick qui casse une brique emet BRIQUE_DETRUITE ---
	var s = State.initial(1)
	s.ball_pos = Vector2(P.BRIQUE_LARGEUR / 2.0, s.start_y + 4.0)
	s.ball_vel = Vector2(0.0, 120.0)
	var r: Dictionary = Loop.step(s, 0)
	var a_casse := false
	for e in r["evenements"]:
		if e["type"] == Events.BRIQUE_DETRUITE:
			a_casse = true
	h.eq(a_casse, true, "un tick qui casse une brique emet BRIQUE_DETRUITE")
	h.eq(r["etat"].briques_restantes, s.briques_restantes - 1, "la brique est reellement detruite (compte -1)")

	# ============================================================================
	# DURCISSEMENT MUTATION — loop.gd : l'emission d'evenements suit des bornes STRICTES.
	# REBOND_MUR ssi une face de mur est touchee (!= AUCUN) ; FIN_PARTIE ssi le tick FAIT
	# TRANSITER de EN_COURS vers un terminal (bornes ==/and/!= de la fin de partie).
	# ============================================================================
	# Un tick interieur SANS contact mur et SANS transition : ni REBOND_MUR ni FIN_PARTIE.
	var libre = State.initial(1)
	libre.ball_pos = Vector2(P.TERRAIN_LARGEUR / 2.0, P.TERRAIN_HAUTEUR / 2.0)  # loin murs/briques/raquette
	libre.ball_vel = Vector2(0.0, 100.0)
	var r_libre: Dictionary = Loop.step(libre, 0)
	var murs := 0
	var fins := 0
	for e in r_libre["evenements"]:
		if e["type"] == Events.REBOND_MUR:
			murs += 1
		if e["type"] == Events.FIN_PARTIE:
			fins += 1
	h.eq(murs, 0, "aucun mur touche -> 0 REBOND_MUR (borne != AUCUN)")
	h.eq(fins, 0, "tick sans transition -> 0 FIN_PARTIE (bornes ==/and/!= de la fin)")
	h.eq(r_libre["etat"].statut, State.Statut.EN_COURS, "tick sans transition -> reste EN_COURS")
	# Un tick AVEC contact mur gauche : EXACTEMENT 1 REBOND_MUR et vx inverse dans le tick.
	var mur = State.initial(1)
	mur.ball_pos = Vector2(P.BALLE_RAYON, P.TERRAIN_HAUTEUR / 2.0)
	mur.ball_vel = Vector2(-100.0, 0.0)
	var r_mur: Dictionary = Loop.step(mur, 0)
	var murs_g := 0
	for e in r_mur["evenements"]:
		if e["type"] == Events.REBOND_MUR:
			murs_g += 1
	h.eq(murs_g, 1, "mur gauche touche -> EXACTEMENT 1 REBOND_MUR")
	h.eq(r_mur["etat"].ball_vel.x, 100.0, "mur gauche -> vx inverse (strict) dans le tick")
	# TRANSITION vers PERDU : derniere vie perdue ce tick -> EXACTEMENT 1 FIN_PARTIE(PERDU).
	var perd = State.initial(1)
	perd.vies = 1
	perd.ball_pos = Vector2(P.TERRAIN_LARGEUR / 2.0, P.TERRAIN_HAUTEUR + P.BALLE_RAYON + 5.0)
	perd.ball_vel = Vector2(0.0, 100.0)
	var r_perd: Dictionary = Loop.step(perd, 0)
	var fins_p := 0
	var statut_p := -1
	for e in r_perd["evenements"]:
		if e["type"] == Events.FIN_PARTIE:
			fins_p += 1
			statut_p = e["statut"]
	h.eq(r_perd["etat"].statut, State.Statut.PERDU, "derniere vie perdue -> statut PERDU")
	h.eq(fins_p, 1, "transition EN_COURS->terminal -> EXACTEMENT 1 FIN_PARTIE")
	h.eq(statut_p, State.Statut.PERDU, "FIN_PARTIE porte le statut terminal (PERDU)")
	# TRANSITION vers GAGNE : derniere brique cassee ce tick -> EXACTEMENT 1 FIN_PARTIE(GAGNE).
	var gagne = State.initial(1)
	for i in range(gagne.bricks.size()):
		gagne.bricks[i] = false
	gagne.bricks[BrickField.index(0, 0)] = true
	gagne.briques_restantes = 1
	gagne.ball_pos = Vector2(P.BRIQUE_LARGEUR / 2.0, gagne.start_y)
	gagne.ball_vel = Vector2(0.0, 120.0)
	var r_gagne: Dictionary = Loop.step(gagne, 0)
	var fins_g := 0
	for e in r_gagne["evenements"]:
		if e["type"] == Events.FIN_PARTIE and e["statut"] == State.Statut.GAGNE:
			fins_g += 1
	h.eq(r_gagne["etat"].briques_restantes, 0, "derniere brique cassee -> 0 restante")
	h.eq(r_gagne["etat"].statut, State.Statut.GAGNE, "0 brique -> statut GAGNE")
	h.eq(fins_g, 1, "victoire -> EXACTEMENT 1 FIN_PARTIE(GAGNE)")
