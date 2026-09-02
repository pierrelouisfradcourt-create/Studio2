# v2_level_alt_descriptor.gd — ligne level.alt_descriptor, capacites F94/F101/F103.
# La SECONDE carte a des dimensions et un plan DIFFERENTS de la premiere : c'est elle qui
# rend falsifiable la propriete « aucune constante de logique n'encode une carte ». Une
# seule carte ne prouverait rien.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")

var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var desc: Dictionary = ContentV2.descripteur(1)
	h.eq(desc.is_empty(), false, "level.alt: le descripteur est lisible")
	h.eq(String(desc["id"]), "maze_alt", "level.alt: identifiant declare")
	h.eq(Schema.champs_manquants(desc).size(), 0, "level.alt: meme jeu de champs obligatoires")
	h.eq(Schema.symboles_inconnus(desc["plan"]).size(), 0, "level.alt: meme legende fermee")

	# DIMENSIONS DIFFERENTES : c'est la condition de falsifiabilite.
	h.ok(Alt.LARGEUR != Maze.LARGEUR, "level.alt: largeur differente de la carte nominale")
	h.ok(Alt.HAUTEUR != Maze.HAUTEUR, "level.alt: hauteur differente de la carte nominale")
	h.ok(Alt.PLAN != Maze.PLAN, "level.alt: plan different de la carte nominale")
	h.ok(Alt.DEPART_PACMAN != Maze.DEPART_PACMAN, "level.alt: depart different")

	# Elle est VALIDE et porte un nombre de collectibles PROPRE, jamais celui de l'autre.
	var v: Dictionary = Validator.verifier(desc)
	h.eq(v["valide"], true, "level.alt: verdict de validite favorable")
	var total_alt: int = Pellets.total_pose(Pellets.poser(Alt))
	var total_classique: int = Pellets.total_pose(Pellets.poser(Maze))
	h.gt(total_alt, 0, "level.alt: des collectibles sont poses")
	h.ok(total_alt != total_classique, "level.alt: total de collectibles propre a la carte")
	h.eq(total_alt, 172, "level.alt: 172 collectibles, comptes et non recopies")
	h.eq(Pellets.tous_atteignables(Alt, Pellets.poser(Alt), Alt.DEPART_PACMAN), true,
		"level.alt: tous les collectibles sont atteignables depuis le depart")
