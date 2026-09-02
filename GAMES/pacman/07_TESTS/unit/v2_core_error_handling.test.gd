# v2_core_error_handling.test.gd — ligne core.error_handling, capacite F97.
# Volet V2 le plus expose : le contenu devenant une DONNEE, la donnee malformee devient
# la premiere entree hors domaine du jeu. Elle ne casse pas la partie en cours.
extends RefCounted

const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# Une partie en cours SURVIT a la lecture d'un descripteur malforme : le refus est
	# rendu, l'etat n'est pas touche.
	var jeu = State.initial(Maze, 3)
	var avant = jeu.clone()
	for mauvais in [{}, {"id": "x"}, {"id": "x", "nom": "y", "plan": "pas un tableau"}]:
		var v: Dictionary = Validator.verifier(mauvais)
		h.eq(v["valide"], false, "core.error: un descripteur malforme est refuse")
	h.eq(jeu.egal_profond(avant), true, "core.error: la partie en cours est intacte")

	# Le jeu continue d'avancer apres le refus.
	var apres = Loop.step(jeu, Maze.DEPART_DIRECTION)["etat"]
	h.eq(apres.ticks, 1, "core.error: la partie avance encore")
	h.eq(apres.statut, State.Statut.EN_COURS, "core.error: elle reste jouable")

	# Un descripteur ABSENT (fichier inexistant) rend un dictionnaire vide, pas une erreur.
	h.eq(ContentV2.descripteur_du_dossier("carte_qui_n_existe_pas").is_empty(), true,
		"core.error: un dossier absent rend un descripteur vide")
	h.eq(ContentV2.lire_json("res://fichier_absent.json").is_empty(), true,
		"core.error: un fichier absent rend un dictionnaire vide")

	# Un ETAT hors domaine se CONSTATE : est_valide refuse, il ne leve pas.
	h.eq(jeu.est_valide(), true, "core.error: un etat sain est valide")
	var casse = jeu.clone()
	casse.statut = 42
	h.eq(casse.est_valide(), false, "core.error: un statut hors vocabulaire est refuse")
	var casse2 = jeu.clone()
	casse2.vies = -1
	h.eq(casse2.est_valide(), false, "core.error: un compteur de vies negatif est refuse")
	var casse3 = jeu.clone()
	casse3.pac = Vector2i(0, 0)
	h.eq(casse3.est_valide(), false, "core.error: un joueur dans un mur est refuse")
	var casse4 = jeu.clone()
	casse4.niveau = 0
	h.eq(casse4.est_valide(), false, "core.error: un numero de niveau hors domaine est refuse")
	var casse5 = jeu.clone()
	casse5.mode = 7
	h.eq(casse5.est_valide(), false, "core.error: un mode hors vocabulaire est refuse")
	var casse6 = jeu.clone()
	casse6.carte = null
	h.eq(casse6.est_valide(), false, "core.error: un etat sans carte est refuse")
