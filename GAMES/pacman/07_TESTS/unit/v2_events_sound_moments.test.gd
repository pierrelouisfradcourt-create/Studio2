# v2_events_sound_moments.test.gd — ligne events.sound_moments, capacite F88.
# SIX MOMENTS SONORES NOMMES, DERIVES de la comparaison avant/apres et de la transition
# d'application. Aucune API audio n'est referencee ici — c'est cette absence qui est comptee.
extends RefCounted

const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	h.eq(Events.MOMENTS.size(), 6, "events.sons: six moments nommes")
	var doublons: int = 0
	for i in range(6):
		for j in range(i + 1, 6):
			if Events.MOMENTS[i] == Events.MOMENTS[j]:
				doublons += 1
	h.eq(doublons, 0, "events.sons: six noms deux a deux differents")
	h.eq(Events.moment_connu("son_mort"), true, "events.sons: un moment declare est connu")
	h.eq(Events.moment_connu("son_inconnu"), false, "events.sons: un moment non declare est refuse")

	# DERIVATION : chaque moment vient d'une comparaison avant/apres.
	var avant = State.initial(Maze, 5)
	var apres = Loop.step(avant, Maze.DEPART_DIRECTION)["etat"]
	h.eq(Events.a_avance(avant, apres), true, "events.sons: l'avancee est derivee des positions")
	h.eq(Events.a_avance(avant, avant), false, "events.sons: sans deplacement, aucune avancee")
	h.eq(Events.a_collecte(avant, apres), true, "events.sons: la collecte est derivee du compteur")
	var mort = avant.clone()
	mort.vies = avant.vies - 1
	h.eq(Events.a_perdu_une_vie(avant, mort), true, "events.sons: la mort est derivee du compteur de vies")
	var effraye = avant.clone()
	Chase.armer_effraye(effraye)
	h.eq(Events.est_entre_en_effraye(avant, effraye), true, "events.sons: l'entree en Effraye est derivee")
	h.eq(Events.est_entre_en_effraye(effraye, avant), false, "events.sons: la sortie n'est pas une entree")
	var gagne = avant.clone()
	gagne.statut = State.Statut.GAGNE
	h.eq(Events.a_gagne(avant, gagne), true, "events.sons: la victoire est derivee du statut")

	# LA PAUSE est REMISE par l'appelant : elle ne se lit pas dans l'etat de partie.
	h.eq(Events.evenements_sonores(avant, avant, true).has(Events.SON_PAUSE), true,
		"events.sons: l'ouverture de menu produit le moment de pause")
	h.eq(Events.evenements_sonores(avant, avant, false).size(), 0,
		"events.sons: sans changement ni menu, aucun moment")

	# COMPTAGE : aucune API audio dans la logique, controle positif dans le runtime.
	h.eq(Purity.audio_dans_logique().size(), 0, "events.sons: 0 fichier de logique reference une API audio")
	h.gt(Purity.audio_dans_runtime().size(), 0, "events.sons: le controle positif les trouve dans le runtime")
