# v2_bindings_table.test.gd — ligne bindings.table, capacite F77.
# TABLE DE LIAISONS enumerable par intention et par peripherique. C'est ICI, et dans
# aucun fichier de logique, que vivent les codes de touches et de boutons : d'ou le
# CONTROLE POSITIF sans lequel le comptage a 0 dans 05_SYSTEMS ne prouverait rien.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	h.eq(Bindings.PERIPHERIQUES.size(), 3, "bindings.table: trois peripheriques declares")
	h.eq(Bindings.PERIPHERIQUE_REFERENCE, Bindings.MANETTE, "bindings.table: la manette est la reference")
	h.eq(Bindings.intentions_liees().size(), 10, "bindings.table: dix intentions liees")

	# ENUMERABLE : chaque intention liee rend une liste par peripherique.
	var sans_liste: int = 0
	for i in Bindings.intentions_liees():
		for p in Bindings.PERIPHERIQUES:
			if not (Bindings.liaisons(i, p) is Array):
				sans_liste += 1
	h.eq(sans_liste, 0, "bindings.table: chaque couple intention/peripherique rend une liste")
	h.eq(Bindings.liaisons(Intents.Intention.AUCUNE, Bindings.CLAVIER).size(), 0,
		"bindings.table: l'absence d'intention n'a aucune liaison")
	h.eq(Bindings.liaisons(Intents.Intention.HAUT, "peripherique_inconnu").size(), 0,
		"bindings.table: un peripherique inconnu rend une liste vide")

	# LES CODES vivent ici : controle positif obligatoire.
	h.gt(Bindings.nombre_de_liaisons(Bindings.CLAVIER), 0, "bindings.table: des liaisons clavier declarees")
	h.gt(Bindings.nombre_de_liaisons(Bindings.MANETTE), 0, "bindings.table: des liaisons manette declarees")
	h.gt(Bindings.nombre_de_liaisons(Bindings.TACTILE), 0, "bindings.table: des liaisons tactiles declarees")
	h.eq(Purity.entree_dans_logique().size(), 0, "bindings.table: 0 code de touche dans la logique")
	h.gt(Purity.entree_dans_runtime().size(), 0, "bindings.table: les memes codes sont trouves dans le runtime")

	# RESOLUTION : une touche liee rend son intention, une touche libre rend AUCUNE.
	var touche_haut: int = Bindings.liaisons(Intents.Intention.HAUT, Bindings.CLAVIER)[0]
	h.eq(Bindings.intention_de_touche(touche_haut), Intents.Intention.HAUT, "bindings.table: touche resolue")
	h.eq(Bindings.intention_de_touche(KEY_F13), Intents.Intention.AUCUNE, "bindings.table: touche non liee")
	var bouton_haut: int = Bindings.liaisons(Intents.Intention.HAUT, Bindings.MANETTE)[0]
	h.eq(Bindings.intention_de_bouton(bouton_haut), Intents.Intention.HAUT, "bindings.table: bouton resolu")
	h.eq(Bindings.intention_de_zone(Bindings.ZONE_PAUSE), Intents.Intention.PAUSE, "bindings.table: zone resolue")
	h.eq(Bindings.intention_de_zone("zone_inconnue"), Intents.Intention.AUCUNE, "bindings.table: zone inconnue")
