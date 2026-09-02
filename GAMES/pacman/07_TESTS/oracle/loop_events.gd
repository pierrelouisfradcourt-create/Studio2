# loop_events.gd — ligne loop.events, capacite F40.
# La liste d'evenements du tick est la SEULE prise a laquelle un adaptateur de retour
# peut se brancher. L'evenement de bascule est emis AU tick du seuil, ce qui rend
# l'indication d'etat lisible a l'ecran differente entre les deux releves.
extends RefCounted

const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Banner = preload("res://06_RUNTIME/adapters/presentation/state_banner.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Vocabulaire FERME des evenements.
	var vocabulaire: Array = [
		Loop.EV_PASTILLE, Loop.EV_SUPER, Loop.EV_BASCULE,
		Loop.EV_CAPTURE, Loop.EV_VIE_PERDUE, Loop.EV_FIN,
	]
	h.eq(vocabulaire.size(), 6, "loop.events: six evenements declares")

	# Consommation d'une pastille ordinaire -> evenement de pastille.
	var s = State.initial(Maze, 1)
	var ordinaire := Vector2i(-1, -1)
	for i in range(s.pastilles.size()):
		if s.pastilles[i] == Pellets.Contenu.PASTILLE:
			ordinaire = Maze.case_de(i)
			break
	s.pac = Maze.case_suivante(ordinaire, Maze.DROITE)
	s.pac_dir = Maze.GAUCHE
	for i in range(4):
		s.dehors[i] = false
		s.sorties_maison[i] = 99999
	var sortie: Dictionary = Loop.step(s, Maze.GAUCHE)
	h.ok(sortie["evenements"].has(Loop.EV_PASTILLE), "loop.events: evenement de pastille emis")
	h.eq(sortie["evenements"].has(Loop.EV_SUPER), false, "loop.events: pas d'evenement de super-pastille")

	# Consommation d'une super-pastille -> evenement de super-pastille.
	var t = State.initial(Maze, 1)
	var superp: Vector2i = Pellets.positions_super(Maze, t.pastilles)[0]
	t.pac = Maze.case_suivante(superp, Maze.BAS)
	t.pac_dir = Maze.HAUT
	for i in range(4):
		t.dehors[i] = false
		t.sorties_maison[i] = 99999
	var sortie2: Dictionary = Loop.step(t, Maze.HAUT)
	h.ok(sortie2["evenements"].has(Loop.EV_SUPER), "loop.events: evenement de super-pastille emis")

	# Aucun evenement sur un tick sans rien : la liste n'est jamais remplie par defaut.
	var u = State.initial(Maze, 1)
	u.pac = Maze.DEPART_PACMAN
	u.pac_dir = Maze.BAS
	for i in range(4):
		u.dehors[i] = false
		u.sorties_maison[i] = 99999
	var sortie3: Dictionary = Loop.step(u, Maze.AUCUNE)
	h.eq(sortie3["evenements"], [], "loop.events: aucun evenement sur un tick sans rien")

	# BASCULE — l'evenement est emis AU tick du seuil, et l'indication a l'ecran DIFFERE
	# entre le releve precedent et celui du seuil.
	var jeu = State.initial(Maze, 1)
	for i in range(4):
		jeu.dehors[i] = true
		jeu.sorties_maison[i] = 0
	var bascule_au_seuil: bool = false
	var indication_differente: bool = false
	var seuils_vus: int = 0
	for _t in range(Chase.seuils()[0] + 60):
		if jeu.statut != State.Statut.EN_COURS:
			break
		var releve_avant: Dictionary = Observable.projeter(jeu)
		var pas: Dictionary = Loop.step(jeu, Bot.choisir_action(jeu))
		jeu = pas["etat"]
		if Chase.est_seuil(jeu.horloge):
			seuils_vus += 1
			bascule_au_seuil = pas["evenements"].has(Loop.EV_BASCULE)
			indication_differente = Banner.indication_differente(releve_avant, Observable.projeter(jeu))
			break
	h.eq(seuils_vus, 1, "loop.events: un seuil a bien ete atteint")
	h.eq(bascule_au_seuil, true, "loop.events: l'evenement de bascule est emis AU tick du seuil")
	h.eq(indication_differente, true,
		"loop.events: l'indication d'etat lisible differe entre les deux releves")
