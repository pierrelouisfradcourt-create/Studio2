# world_scope_declaration.test.gd — ligne world.scope_declaration.
# La forme de l'etat declare TROIS portees (globale, zone, session) et non deux. Cette
# ligne ne prouve aucun monde multi-zone : elle prouve que la DECLARATION est complete,
# disjointe, et qu'elle redecoupe exactement ce que level_progression declarait deja.
# Sans elle, la troisieme portee serait une frontiere non executee.
extends RefCounted

const World = preload("res://05_SYSTEMS/world_state/world_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# --- LA PARTITION ---
	h.eq(World.portees_disjointes(), true, "world.scope: un champ a une portee, jamais deux")
	h.eq(World.partition_couvre_progression(), true,
		"world.scope: la partition redecoupe exactement level_progression")
	h.eq(World.champs_sans_portee(), [], "world.scope: aucun champ declare sans portee")
	h.eq(World.PORTEES.size(), 3, "world.scope: exactement trois portees")

	# CONTROLE POSITIF : la portee est bien LUE, pas devinee.
	h.eq(World.portee_de("score"), World.NOM_GLOBALE, "world.scope: le score est global")
	h.eq(World.portee_de("pastilles"), World.NOM_ZONE, "world.scope: les collectibles sont de zone")
	h.eq(World.portee_de("pac"), World.NOM_SESSION, "world.scope: la position est de session")
	h.eq(World.portee_de("champ_inexistant"), World.NOM_ABSENT,
		"world.scope: un champ inconnu n'a pas de portee, et ne leve pas")

	# CE QUE level_progression CONSERVE est exactement CE QUI EST GLOBAL.
	for champ in Progression.CONSERVES:
		h.eq(World.portee_de(champ), World.NOM_GLOBALE,
			"world.scope: %s traverse la bascule, donc il est global" % champ)

	# --- LA FORME DE L'ETAT ---
	var a = State.initial(Maze, 1)
	h.eq(a.zone, World.AUCUNE_ZONE, "world.scope: une partie mono-zone ne declare aucune zone")
	h.eq(a.memoire_zones.is_empty(), true, "world.scope: aucune zone memorisee au depart")

	# Les deux champs SUIVENT le clone et la comparaison profonde.
	var c = a.clone()
	h.eq(c.egal_profond(a), true, "world.scope: le clone reste strictement egal")
	c.zone = "piece_nord"
	h.eq(c.egal_profond(a), false, "world.scope: deux etats de zones differentes ne sont pas egaux")

	# --- MEMORISER / RAPPELER ---
	var b = State.initial(Maze, 1)
	b.consommees = 7
	var memoire: Dictionary = World.memoriser({}, "piece_nord", b)
	h.eq(memoire.has("piece_nord"), true, "world.scope: la zone quittee est memorisee")
	h.eq(int(World.rappeler(memoire, "piece_nord")["consommees"]), 7,
		"world.scope: elle se rappelle ce qui y a ete consomme")
	h.eq(World.rappeler(memoire, "piece_jamais_visitee"), {},
		"world.scope: une zone jamais quittee ne rappelle rien, et ne leve pas")
	h.eq(World.rappeler(memoire, World.AUCUNE_ZONE), {},
		"world.scope: l'absence de zone ne rappelle rien")

	# PURETE : memoriser ne mute pas son entree.
	var origine: Dictionary = {}
	World.memoriser(origine, "piece_nord", b)
	h.eq(origine.is_empty(), true, "world.scope: memoriser ne mute pas la memoire recue")
	h.eq(World.memoriser({}, World.AUCUNE_ZONE, b).is_empty(), true,
		"world.scope: sans zone, rien n'est memorise")

	# --- RESTAURER ---
	var vierge = State.initial(Maze, 1)
	var inchange = World.restaurer(vierge, {})
	h.eq(inchange.egal_profond(vierge), true,
		"world.scope: une memoire vide restaure un etat strictement identique")

	var restaure = World.restaurer(vierge, World.rappeler(memoire, "piece_nord"))
	h.eq(restaure.consommees, 7, "world.scope: revenir dans la zone retrouve son etat")
	h.eq(vierge.consommees, 0, "world.scope: restaurer ne mute pas l'etat recu")
	h.eq(restaure.score, vierge.score, "world.scope: la restauration ne touche pas le global")
	h.eq(restaure.pac, vierge.pac, "world.scope: elle ne touche pas la session non plus")
