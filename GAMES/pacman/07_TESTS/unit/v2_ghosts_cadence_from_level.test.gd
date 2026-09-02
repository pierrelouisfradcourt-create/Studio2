# v2_ghosts_cadence_from_level.test.gd — ligne ghosts.cadence_from_level, capacite F108.
# La CADENCE prend la valeur du parametre de progression du niveau courant, PASSEE EN
# ARGUMENT — jamais lue dans une table indexee par niveau, ce qui rendrait l'ajout d'un
# niveau dependant de ce fichier.
extends RefCounted

const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# La cadence ARRIVE : elle n'est jamais cherchee.
	h.eq(Ghosts.periode_effective(24), 24, "ghosts.cadence: la valeur recue est utilisee telle quelle")
	h.eq(Ghosts.periode_effective(20), 20, "ghosts.cadence: idem pour une autre valeur")
	h.eq(Ghosts.periode_effective(0), P.CADENCE_FANTOME_PERIODE, "ghosts.cadence: 0 retombe sur le repli")
	h.eq(Ghosts.periode_effective(1), P.CADENCE_FANTOME_PERIODE, "ghosts.cadence: 1 retombe sur le repli")

	# CONTRAINTE DURE : le fantome saute un tick sur la periode, donc reste STRICTEMENT
	# plus lent que Pac-Man, quelle que soit la valeur du niveau.
	for periode in [20, 24]:
		var sauts: int = 0
		for t in range(periode * 2):
			if not Ghosts.bouge_ce_tick(t, false, periode):
				sauts += 1
		h.eq(sauts, 2, "ghosts.cadence: exactement deux ticks sautes sur deux periodes")
		h.gt(sauts, 0, "ghosts.cadence: le fantome est strictement plus lent que Pac-Man")

	# DEUX VALEURS DISTINCTES donnent DEUX comportements distincts.
	var differences: int = 0
	for t in range(48):
		if Ghosts.bouge_ce_tick(t, false, 20) != Ghosts.bouge_ce_tick(t, false, 24):
			differences += 1
	h.gt(differences, 0, "ghosts.cadence: deux cadences donnent deux comportements distincts")

	# L'ETAT porte la cadence de SON niveau, lue dans le catalogue.
	var e1 = State.initial(Maze, 1, ContentV2.cadence(0))
	var e2 = State.initial(Alt, 1, ContentV2.cadence(1))
	h.eq(e1.cadence_fantome, 20, "ghosts.cadence: le premier niveau porte sa cadence")
	h.eq(e2.cadence_fantome, 24, "ghosts.cadence: le second niveau porte la sienne")
	h.ok(e1.cadence_fantome != e2.cadence_fantome, "ghosts.cadence: les deux valeurs different")

	# AUCUNE TABLE indexee par niveau dans le module.
	var f := FileAccess.open("res://05_SYSTEMS/ghost_movement/ghost_movement.gd", FileAccess.READ)
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("CADENCES_PAR_NIVEAU"), false, "ghosts.cadence: aucune table par niveau")
	h.eq(texte.contains("level_progression"), false, "ghosts.cadence: le module ne connait pas la progression")
	h.eq(texte.contains("content_provider"), false, "ghosts.cadence: le module ne va chercher aucun contenu")

	# L'etat Effraye garde sa propre cadence, independante du niveau.
	h.eq(Ghosts.bouge_ce_tick(2, true, 24), true, "ghosts.cadence: l'Effraye bouge un tick sur deux")
	h.eq(Ghosts.bouge_ce_tick(3, true, 24), false, "ghosts.cadence: et pas l'autre")
