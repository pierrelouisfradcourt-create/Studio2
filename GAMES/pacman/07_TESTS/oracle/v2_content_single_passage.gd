# v2_content_single_passage.gd — ligne content.single_passage, capacites F95/F99.
# SEUL passage entre la donnee inerte et la logique pure : la logique ne va JAMAIS
# chercher un contenu, c'est le contenu qui lui est REMIS EN ARGUMENT.
extends RefCounted

const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# SENS UNIQUE : aucun fichier de logique ne cite un chemin de contenu.
	var fautifs: Array = Purity.fichiers_portant("res://05_SYSTEMS", ["03_WORLD", "level.json", "catalog.json"])
	h.eq(fautifs.size(), 0, "content.passage: 0 fichier de logique ne cite un chemin de contenu")
	var lecteurs: Array = Purity.fichiers_portant("res://06_RUNTIME", ["03_WORLD"])
	h.gt(lecteurs.size(), 0, "content.passage: le contenu est lu du cote runtime — controle positif")

	# Aucun fichier de logique n'ouvre de fichier du tout.
	var io: Array = Purity.fichiers_portant("res://05_SYSTEMS", ["FileAccess", "DirAccess"])
	h.eq(io.size(), 0, "content.passage: aucune entree-sortie dans la logique")

	# LE FOURNISSEUR remet la donnee, il ne construit pas la topologie.
	var f := FileAccess.open("res://06_RUNTIME/adapters/content_provider/content_provider.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("depuis_descripteur"), false, "content.passage: le fournisseur ne construit pas la carte")
	h.eq(texte.contains("FileAccess"), true, "content.passage: c'est bien lui qui lit les fichiers")

	# LE DESCRIPTEUR est REMIS a la logique, qui en fait une carte.
	var desc: Dictionary = ContentV2.descripteur(0)
	var carte = MazeClass.depuis_descripteur(desc)
	h.eq(carte.ID, "maze_classic", "content.passage: la carte est construite depuis la donnee remise")
	var jeu = State.initial(carte, 1)
	h.eq(jeu.carte.meme_carte(carte), true, "content.passage: l'etat porte la carte remise")

	# Le point de passage OBLIGE : la carte passe par le verdict avant d'etre jouee.
	var v: Dictionary = Validator.carte_validee(desc)
	h.eq(v["valide"], true, "content.passage: la carte est validee avant d'etre jouee")
	h.ok(v["carte"] != null, "content.passage: le verdict rend la carte")
