# v2_level_classic_descriptor.gd — ligne level.classic_descriptor, capacites F94/F97/F103.
# Le descripteur de la carte NOMINALE est AUTOPORTANT et INERTE : tout ce que la logique
# V1 lisait dans des constantes est porte par cette donnee, et rien d'autre n'y vit.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")


func run(h) -> void:
	var desc: Dictionary = ContentV2.descripteur(0)
	h.eq(desc.is_empty(), false, "level.classic: le descripteur est lisible")
	h.eq(String(desc["id"]), "maze_classic", "level.classic: identifiant declare")
	h.eq(Schema.champs_manquants(desc).size(), 0, "level.classic: aucun champ obligatoire manquant")
	h.eq(Schema.symboles_inconnus(desc["plan"]).size(), 0, "level.classic: aucun symbole hors legende")
	h.eq(Schema.plan_rectangulaire(desc["plan"]), true, "level.classic: plan rectangulaire")

	# Les grandeurs autrefois figees en constantes sont portees par la donnee.
	h.eq(Maze.LARGEUR, 28, "level.classic: largeur 28 derivee du plan")
	h.eq(Maze.HAUTEUR, 36, "level.classic: hauteur 36 derivee du plan")
	h.eq(Maze.DEPART_PACMAN, Vector2i(13, 26), "level.classic: depart declare")
	h.eq(Maze.DEPART_DIRECTION, MazeClass.GAUCHE, "level.classic: direction de depart declaree")
	h.eq(Maze.MAISON_CENTRE, Vector2i(13, 17), "level.classic: centre de maison declare")
	h.eq(Maze.SORTIE_MAISON, Vector2i(13, 14), "level.classic: sortie de maison declaree")
	h.eq(Maze.PLACES_MAISON.size(), 4, "level.classic: quatre places de maison")

	# DONNEE PURE : aucun comportement, aucun import. Le descripteur ne porte que des
	# champs declares, jamais un chemin de script.
	var texte: String = JSON.stringify(desc)
	h.eq(texte.contains("preload"), false, "level.classic: aucun import dans la donnee")
	h.eq(texte.contains("res://"), false, "level.classic: aucun chemin de ressource dans la donnee")

	# La carte est VALIDE : elle est jouable, pas seulement lisible.
	var v: Dictionary = Validator.verifier(desc)
	h.eq(v["valide"], true, "level.classic: verdict de validite favorable")
	h.eq(v["motifs"].size(), 0, "level.classic: aucun motif de refus")
