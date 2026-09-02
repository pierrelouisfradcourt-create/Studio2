# v2_harness_no_color_in_logic.gd — ligne harness.no_color_in_logic, capacite F111.
# Le comptage des fichiers de 05_SYSTEMS portant un litteral de couleur vaut exactement
# 0, COMME sur le jeu du run V1. Propriete DEJA ACQUISE : le travail de cette ligne est
# de NE PAS LA CASSER en ajoutant l'identite visuelle, et de le MESURER.
extends RefCounted

const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	var m: Dictionary = Purity.mesurer()
	h.gt(m["fichiers_logique"], 0, "harness.couleur: des fichiers de logique ont ete parcourus")
	h.gt(m["fichiers_runtime"], 0, "harness.couleur: des fichiers de runtime aussi")
	h.eq(m["couleur_logique"], 0, "harness.couleur: 0 fichier de logique porte un litteral de couleur")
	h.eq(m["couleur_hors_palette"], 0, "harness.couleur: 0 litteral hors du descripteur de palette")
	h.eq(m["couleur_palette"], 1, "harness.couleur: le descripteur en porte — controle positif")

	# MEME HARNAIS, memes controles positifs, pour les deux autres comptages.
	h.eq(m["entree_logique"], 0, "harness.couleur: 0 API d'entree dans la logique")
	h.gt(m["entree_runtime"], 0, "harness.couleur: les memes trouvees dans le runtime")
	h.eq(m["audio_logique"], 0, "harness.couleur: 0 API audio dans la logique")
	h.gt(m["audio_runtime"], 0, "harness.couleur: les memes trouvees dans le runtime")

	# LE COMPTAGE porte sur le CODE : un commentaire qui NOMME une API n'est pas une
	# reference. Limite de mesure assumee et nommee, pas un silence.
	h.eq(Purity.code_seul("var x = 1 # Color(1,0,0)").contains("Color("), false,
		"harness.couleur: le commentaire est retire avant comptage")
	h.eq(Purity.code_seul("var c = Color(1,0,0)").contains("Color("), true,
		"harness.couleur: le code, lui, est bien compte")
	h.eq(Purity.fichiers_gd("res://05_SYSTEMS").size(), m["fichiers_logique"],
		"harness.couleur: le comptage porte sur les fichiers reellement listes")
