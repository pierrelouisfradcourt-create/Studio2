# v2_palette_single_descriptor.test.gd — ligne palette.single_descriptor, capacite F110.
# Descripteur de palette UNIQUE, consomme par TOUS les ecrans : changer ce seul module
# change l'apparence de tous les ecrans a la fois. Le comptage des litteraux de couleur
# situes hors du descripteur vaut exactement 0.
extends RefCounted

const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const Banner = preload("res://06_RUNTIME/adapters/presentation/state_banner.gd")


func run(h) -> void:
	# UNICITE DU LIEU : 0 litteral de couleur hors du descripteur, sur tout le runtime.
	h.eq(Purity.couleur_hors_palette().size(), 0, "palette.unique: 0 litteral de couleur hors du descripteur")
	# CONTROLE POSITIF : le descripteur, lui, en porte — sinon le comptage ne prouve rien.
	h.eq(Purity.couleur_dans_palette().size(), 1, "palette.unique: le descripteur porte bien des couleurs")
	h.eq(Purity.couleur_dans_logique().size(), 0, "palette.unique: 0 litteral de couleur dans la logique")

	# LES CONSOMMATEURS lisent le descripteur, ils ne redeclarent rien.
	h.eq(MazeView.COULEUR_MUR, Palette.MUR, "palette.unique: la vue lit la palette")
	h.eq(MazeView.COULEUR_PACMAN, Palette.PACMAN, "palette.unique: idem pour le joueur")
	h.eq(MazeView.COULEURS_FANTOMES, Palette.FANTOMES, "palette.unique: idem pour les fantomes")
	h.eq(Banner.COULEUR_DISPERSION, Palette.ETAT_DISPERSION, "palette.unique: le bandeau lit la palette")

	# LE DESCRIPTEUR est complet et coherent.
	h.gt(Palette.couleurs().size(), 10, "palette.unique: le descripteur declare ses couleurs")
	# V3 : huit entrees ajoutees pour l'identite visuelle procedurale (arete et creux de
	# mur, hors-jeu, super-pastille, lueur, clignotement de fin d'effroi, oeil, pupille).
	# V4 : une de plus, FOND_MODAL, le voile de l'ecran de fin (cause racine P2). Ce
	# compte est un COUNT_FROZEN — une MESURE du descripteur qui se RELEVE quand une
	# entree est ajoutee, jamais un invariant qu'on contourne : c'est le total qui doit
	# suivre le descripteur, et rien d'autre dans cette assertion ne change.
	h.eq(Palette.NOMS.size(), 27, "palette.unique: vingt-sept entrees nommees")
	h.eq(Palette.fantomes_distincts(), true, "palette.unique: quatre couleurs de fantomes distinctes")
	h.eq(Palette.couleur_fantome(0), Palette.FANTOMES[0], "palette.unique: acces nominatif")
	h.eq(Palette.couleur_fantome(9), Palette.TEXTE, "palette.unique: un index hors bornes retombe sur une valeur declaree")
