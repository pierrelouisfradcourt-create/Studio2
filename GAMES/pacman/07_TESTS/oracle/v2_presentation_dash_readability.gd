# v2_presentation_dash_readability.gd — ligne presentation.dash_readability, capacite F87.
# Le dash est rendu VISIBLE a ses DEUX moments : l'instant du declenchement, et la
# periode pendant laquelle il n'est pas encore disponible. L'indication de disponibilite
# est portee A L'ECRAN, pas seulement dans l'etat.
#
# La comparaison d'IMAGES exige une fenetre GPU reelle ; ce qui est mesure ici est la
# LIGNE AFFICHEE aux trois instants, distincte deux a deux.
extends RefCounted

const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	var jeu = State.initial(Maze, 19)
	var avant: Dictionary = Observable.projeter(jeu)
	h.eq(Presentation.dash_pret(avant), true, "presentation.dash: le dash est pret avant le declenchement")
	h.eq(Presentation.mention_dash(avant), Presentation.MENTION_DASH_PRET, "presentation.dash: mention lisible")

	# AU TICK DU DASH.
	jeu = Loop.step(jeu, Maze.DEPART_DIRECTION, true)["etat"]
	var au_dash: Dictionary = Observable.projeter(jeu)
	h.eq(Presentation.dash_pret(au_dash), false, "presentation.dash: il n'est plus pret au tick du dash")
	h.gt(int(au_dash["dash_recharge"]), 0, "presentation.dash: la recharge est armee")

	# PENDANT LA RECHARGE.
	jeu = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	var pendant: Dictionary = Observable.projeter(jeu)
	h.eq(Presentation.dash_pret(pendant), false, "presentation.dash: toujours pas pret pendant la recharge")

	# LES TROIS INDICATIONS AFFICHEES different deux a deux.
	var m1: String = Presentation.mention_dash(avant)
	var m2: String = Presentation.mention_dash(au_dash)
	var m3: String = Presentation.mention_dash(pendant)
	h.ok(m1 != m2, "presentation.dash: avant et au tick du dash different")
	h.ok(m2 != m3, "presentation.dash: au tick et pendant la recharge different")
	h.ok(m1 != m3, "presentation.dash: avant et pendant la recharge different")
	h.eq(m3.contains(Presentation.MENTION_DASH_RECHARGE), true,
		"presentation.dash: la disponibilite est LISIBLE pendant la recharge")

	# LES COULEURS viennent du descripteur et distinguent les deux etats.
	h.ok(Presentation.couleur_dash(avant) != Presentation.couleur_dash(pendant),
		"presentation.dash: la couleur distingue pret et recharge")

	# DASH DESACTIVE : aucune indication affichee, et c'est une valeur declaree.
	var sans = State.initial(Maze, 19, 0, {"dash_actif": false})
	h.eq(Presentation.mention_dash(Observable.projeter(sans)), Presentation.MENTION_DASH_ABSENT,
		"presentation.dash: dash desactive, aucune mention")
