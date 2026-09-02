# v2_end_respawn_from_state_map.test.gd — ligne end.respawn_from_state_map, capacite F100.
# Le repositionnement apres une perte de vie lit les positions de depart de la CARTE
# PORTEE PAR L'ETAT, et non des constantes de la logique.
extends RefCounted

const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Sur CHAQUE carte, la perte de vie replace le joueur au depart DE CETTE CARTE.
	for carte in [Maze, Alt]:
		var s = State.initial(carte, 3)
		s.pac = carte.SORTIE_MAISON
		s.pac_dir = MazeClass.DROITE
		End.perdre_une_vie(s)
		h.eq(s.pac, carte.DEPART_PACMAN, "end.respawn: le joueur revient au depart de sa carte")
		h.eq(s.pac_dir, carte.DEPART_DIRECTION, "end.respawn: direction de depart de sa carte")
		# TRIAGE V6 : DECISION_OBSOLETE sur le symbole. `End.VIES_INITIALES` n'existe plus —
		# les vies dependent du mode. La reference devient celle DU MODE de l'etat, qui est
		# la valeur exacte pour une partie neuve : garde inchangee, symbole corrige.
		h.eq(s.vies, Reglages.vies_initiales(s.mode) - 1, "end.respawn: exactement une vie retiree")
		h.eq(s.horloge, 0, "end.respawn: horloge revenue au premier segment")

	# Les positions differant entre cartes, le respawn differe aussi.
	var a = State.initial(Maze, 3)
	var b = State.initial(Alt, 3)
	End.perdre_une_vie(a)
	End.perdre_une_vie(b)
	h.ok(a.pac != b.pac, "end.respawn: deux cartes, deux positions de respawn")

	# Les collectibles deja consommes ne reviennent PAS.
	var c = State.initial(Maze, 3)
	c.consommees = 12
	End.perdre_une_vie(c)
	h.eq(c.consommees, 12, "end.respawn: les collectibles consommes restent consommes")

	# AUCUNE constante de depart dans le module.
	var f := FileAccess.open("res://05_SYSTEMS/end_conditions/end_conditions.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("DEPART_PACMAN ="), false, "end.respawn: aucune constante de depart")
	h.eq(texte.contains("s.carte.DEPART_PACMAN"), true, "end.respawn: la position vient de la carte de l'etat")
