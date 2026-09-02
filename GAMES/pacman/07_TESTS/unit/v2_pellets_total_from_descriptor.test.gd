# v2_pellets_total_from_descriptor.test.gd — ligne pellets.total_from_descriptor, capacite F98.
# Les collectibles sont poses en lisant la LEGENDE DE LA CARTE RECUE, et le total qui
# definit la victoire est PRODUIT par COMPTAGE — jamais un litteral recopie carte par carte.
extends RefCounted

const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Carte nominale : le total est PRODUIT, et il vaut le compte attendu de cette carte.
	var g1: PackedByteArray = Pellets.poser(Maze)
	h.eq(g1.size(), Maze.nb_cases(), "pellets.total: la grille suit les dimensions de la carte")
	h.eq(Pellets.total_pose(g1), P.COLLECTIBLES_ATTENDUS, "pellets.total: 244 sur la carte nominale")
	h.eq(Pellets.compter(g1, Pellets.Contenu.PASTILLE), P.PASTILLES_ATTENDUES, "pellets.total: 240 pastilles")
	h.eq(Pellets.compter(g1, Pellets.Contenu.SUPER), P.SUPER_ATTENDUES, "pellets.total: 4 super-pastilles")

	# Seconde carte : le MEME code produit un AUTRE total, sans constante modifiee.
	var g2: PackedByteArray = Pellets.poser(Alt)
	h.eq(g2.size(), Alt.nb_cases(), "pellets.total: la grille suit la seconde carte")
	h.eq(Pellets.total_pose(g2), 172, "pellets.total: 172 sur la seconde carte")
	h.ok(Pellets.total_pose(g2) != Pellets.total_pose(g1), "pellets.total: les deux totaux different")
	h.eq(Pellets.compter(g2, Pellets.Contenu.SUPER), 4, "pellets.total: 4 super-pastilles sur la seconde")

	# L'ETAT porte le total de SA carte : la victoire se definit carte par carte.
	var e1 = State.initial(Maze, 1)
	var e2 = State.initial(Alt, 1)
	h.eq(e1.total_pose, Pellets.total_pose(g1), "pellets.total: l'etat porte le total de sa carte")
	h.eq(e2.total_pose, Pellets.total_pose(g2), "pellets.total: idem pour la seconde carte")
	h.ok(e1.total_pose != e2.total_pose, "pellets.total: deux cartes, deux totaux")

	# Aucun litteral de total dans le module : le nombre est compte, pas ecrit.
	var f := FileAccess.open("res://05_SYSTEMS/pellets/pellets.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("244"), false, "pellets.total: aucun total recopie dans le module")
	h.eq(texte.contains("172"), false, "pellets.total: aucun total de seconde carte non plus")

	# CONTENU lu sur la carte RECUE, hors grille compris.
	h.eq(Pellets.contenu_de(Maze, g1, Vector2i(-1, 0)), Pellets.Contenu.VIDE, "pellets.total: hors grille vide")
	h.eq(Pellets.positions_super(Alt, g2).size(), 4, "pellets.total: quatre positions de super sur la seconde")
