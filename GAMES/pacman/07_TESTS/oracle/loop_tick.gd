# loop_tick.gd — ligne loop.tick, capacite F39.
# Deux releves d'etat separes par une fenetre DECLAREE de ticks, sans injecter AUCUNE
# entree : la position de Pac-Man a change et celle d'au moins un fantome a change.
extends RefCounted

const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")

# Fenetre DECLAREE. Elle est courte a dessein : l'exigence impose de n'injecter AUCUNE
# entree, or un Pac-Man qui ne repond pas finit par etre pris — au-dela, on mesurerait
# la perte de vie (qui remet l'horloge a zero) et non l'avancement de la boucle.
const FENETRE: int = 12


func run(h) -> void:
	# ORDRE FIGE et DECLARE du tick — la carte l'exige, il est lisible ici.
	# V2 : le budget de dash s inscrit entre l horloge et le deplacement du joueur. La
	# valeur assertee reste STRICTE et exhaustive — elle suit la carte, elle ne s assouplit pas.
	h.eq(Loop.ORDRE, ["entree", "horloge", "budget_dash", "pac", "fantomes", "consommation", "contacts", "statut"],
		"loop.tick: ordre du tick fige et declare")

	# Le tick NE MUTE JAMAIS son entree : il produit un NOUVEL etat.
	var s = State.initial(Maze, 1)
	var copie = s.clone()
	var sortie: Dictionary = Loop.step(s, Maze.GAUCHE)
	h.eq(s.egal_profond(copie), true, "loop.tick: l'etat d'entree n'est pas mute")
	h.ok(not sortie["etat"].egal_profond(s), "loop.tick: un NOUVEL etat est produit")
	h.eq(sortie["etat"].ticks, s.ticks + 1, "loop.tick: le compteur de ticks avance d'exactement 1")

	# SUR UNE FENETRE DECLAREE, SANS AUCUNE ENTREE : Pac-Man ET un fantome ont bouge.
	var jeu = State.initial(Maze, 1)
	var avant: Dictionary = Observable.projeter(jeu)
	for _t in range(FENETRE):
		jeu = Loop.step(jeu, Maze.AUCUNE)["etat"]
	var apres: Dictionary = Observable.projeter(jeu)

	h.eq(apres["vies"], avant["vies"], "loop.tick: aucune vie perdue sur la fenetre declaree")
	h.eq(apres["tick"] - avant["tick"], FENETRE, "loop.tick: la fenetre declaree a bien ete jouee")
	h.ok(apres["pac"] != avant["pac"], "loop.tick: la position de Pac-Man a change")
	var fantomes_bouges: int = 0
	for i in range(4):
		if apres["fantomes"][i] != avant["fantomes"][i]:
			fantomes_bouges += 1
	h.gt(fantomes_bouges, 0, "loop.tick: au moins un fantome a change de position")

	# L'horloge des etats de poursuite avance avec le tick.
	h.eq(apres["horloge"] - avant["horloge"], FENETRE, "loop.tick: l'horloge avance avec les ticks")

	# DETERMINISME du tick : meme etat, meme entree -> meme etat suivant, champ par champ.
	var a = State.initial(Maze, 3)
	var b = State.initial(Maze, 3)
	var divergences: int = 0
	for _t in range(60):
		a = Loop.step(a, Maze.GAUCHE)["etat"]
		b = Loop.step(b, Maze.GAUCHE)["etat"]
		if not a.egal_profond(b):
			divergences += 1
	h.eq(divergences, 0, "loop.tick: 0 champ divergent sur 60 ticks a entree identique")

	# Un tick joue sur une partie TERMINEE ne change rien.
	var fini = State.initial(Maze, 1)
	fini.consommees = fini.total_pose
	Status.appliquer(fini)
	h.eq(Status.est_terminal(fini.statut), true, "loop.tick: fixture — la partie est bien terminee")
	var gele = fini.clone()
	var apres_fin: Dictionary = Loop.step(fini, Maze.GAUCHE)
	h.eq(apres_fin["etat"].egal_profond(gele), true, "loop.tick: aucun effet sur une partie terminee")
	h.eq(apres_fin["evenements"], [], "loop.tick: aucun evenement sur une partie terminee")
