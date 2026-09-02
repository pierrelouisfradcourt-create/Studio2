# v2_state_carries_map.test.gd — ligne state.carries_map, capacite F99.
# L'etat initial est construit A PARTIR D'UNE CARTE PASSEE EN ENTREE, et l'etat PORTE
# desormais sa carte courante : aucune fonction de la logique ne va chercher une carte
# globale.
extends RefCounted

const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	var a = State.initial(Maze, 1)
	var b = State.initial(Alt, 1)
	h.eq(a.carte.meme_carte(Maze), true, "state.carries: l'etat porte la carte recue")
	h.eq(b.carte.meme_carte(Alt), true, "state.carries: idem pour la seconde carte")
	h.eq(a.carte.meme_carte(b.carte), false, "state.carries: deux etats, deux cartes distinctes")
	h.ok(a.pac != b.pac, "state.carries: chaque etat part du depart de SA carte")
	h.ok(a.total_pose != b.total_pose, "state.carries: chaque etat porte le total de SA carte")

	# La carte SUIT le clone et la comparaison.
	var c = a.clone()
	h.eq(c.carte.meme_carte(a.carte), true, "state.carries: la carte suit le clone")
	h.eq(c.egal_profond(a), true, "state.carries: le clone est strictement egal")
	h.eq(a.egal_profond(b), false, "state.carries: deux etats sur deux cartes ne sont jamais egaux")

	# Un etat SANS carte est refuse : il n'y a pas de carte implicite.
	var sans = a.clone()
	sans.carte = null
	h.eq(sans.est_valide(), false, "state.carries: un etat sans carte est invalide")

	# AUCUNE carte globale dans la logique : aucun fichier de 05_SYSTEMS ne lit 03_WORLD.
	var fautifs: Array = Purity.fichiers_portant("res://05_SYSTEMS", ["03_WORLD", "content_provider", "level.json"])
	h.eq(fautifs.size(), 0, "state.carries: aucun fichier de logique ne va chercher un contenu")
	var lecteurs: Array = Purity.fichiers_portant("res://06_RUNTIME", ["03_WORLD"])
	h.gt(lecteurs.size(), 0, "state.carries: le contenu est lu du cote runtime — controle positif")
	# --- GATE MUTATION : la garde « un etat sans carte n'est egal a rien » -----------
	# Les DEUX membres comptent, et le refus est un FAUX. Un etat prive de sa carte ne
	# peut etre declare egal a un etat qui en porte une — dans un sens comme dans l'autre.
	var sans_carte = a.clone()
	sans_carte.carte = null
	var avec_carte = a.clone()
	h.eq(avec_carte.egal_profond(sans_carte), false,
		"state.carries: un etat avec carte n'egale pas un etat sans carte")
	var deux_sans = sans_carte.clone()
	h.eq(sans_carte.egal_profond(deux_sans), false,
		"state.carries: deux etats sans carte ne sont pas declares egaux non plus")
	h.eq(avec_carte.egal_profond(a), true,
		"state.carries: deux etats portant la meme carte restent egaux")
	# SENS DISCRIMINANT : c'est l'etat PRIVE de carte qui doit refuser la comparaison.
	# Dans l'autre sens les deux formulations de la garde rendent faux et ne prouvent
	# donc rien ; ici, une garde conjonctive laisserait passer la comparaison jusqu'a
	# lire la carte absente.
	h.eq(sans_carte.egal_profond(avec_carte), false,
		"state.carries: un etat sans carte n'egale aucun etat qui en porte une")
