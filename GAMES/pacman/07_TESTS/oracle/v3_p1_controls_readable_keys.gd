# v3_p1_controls_readable_keys.gd — CAUSE RACINE P1.
#
# DEFAUT MESURE (playtest Pierre, aucun oracle ne l'a vu) : l'ecran Controles affichait
# des KEYCODES BRUTS. `liaisons_lisibles` faisait `morceaux.append(str(l))`, et `l` est
# l'entier du moteur — « 4194320 » a la place de « Fleche haut ». Le libelle d'ACTION
# existait deja ; c'est la traduction CODE -> NOM DE TOUCHE qui manquait.
#
# CE QUE CETTE PREUVE MESURE : qu'aucune ligne de l'ecran ne porte de CHIFFRE. Aucun
# libelle d'intention, aucun nom de peripherique, aucun nom de touche declare n'en
# contient : un chiffre a l'ecran ne peut donc venir que d'un code brut. Le compteur
# valait 8 avant la correction (les huit intentions affichees) ; il vaut 0 apres.
extends RefCounted

const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")


func run(h) -> void:
	# LA MESURE QUI TRANCHE : 0 ligne portant un code brut.
	h.eq(Controles.lignes_portant_un_code_brut(), 0,
		"v3.p1: 0 ligne de l'ecran Controles ne porte de code brut")
	h.eq(Controles.lignes().size(), 8, "v3.p1: les huit intentions restent affichees")

	# CONTROLE POSITIF DE L'INSTRUMENT : le detecteur voit bien un chiffre quand il y en
	# a un. Sans lui, un detecteur toujours faux rendrait 0 sans rien prouver.
	h.eq(Bindings.nom_porte_un_code_brut("4194320"), true,
		"v3.p1: l'instrument reconnait un code brut")
	h.eq(Bindings.nom_porte_un_code_brut("Fleche haut"), false,
		"v3.p1: l'instrument accepte un nom humain")

	# CHAQUE liaison declaree porte un nom, et aucun nom ne porte de chiffre.
	h.eq(Bindings.liaisons_sans_nom().size(), 0, "v3.p1: 0 liaison declaree sans nom lisible")
	h.eq(Bindings.noms_portant_un_code_brut().size(), 0, "v3.p1: 0 nom declare portant un chiffre")

	# LA TRADUCTION EST REELLE, verifiee sur les trois peripheriques : le nom rendu est
	# DIFFERENT du code brut qu'affichait la version fautive.
	var codes: int = 0
	for i in Bindings.intentions_liees():
		for p in Bindings.PERIPHERIQUES:
			for l in Bindings.liaisons(i, p):
				if Bindings.nom_liaison(l, p) == str(l):
					codes += 1
	h.eq(codes, 0, "v3.p1: aucun nom n'est le code brut lui-meme")
	h.gt(Bindings.NOMS_CLAVIER.size(), 0, "v3.p1: des noms clavier sont declares")
	h.gt(Bindings.NOMS_MANETTE.size(), 0, "v3.p1: des noms manette sont declares")
	h.gt(Bindings.NOMS_TACTILE.size(), 0, "v3.p1: des noms tactiles sont declares")

	# LE REFUS EST NOMME : une liaison inconnue rend le repli declare, jamais son code.
	h.eq(Bindings.nom_liaison(999999, Bindings.CLAVIER), Bindings.NOM_INCONNU,
		"v3.p1: une liaison inconnue n'a pas de nom")
	h.eq(Controles.nom_lisible(999999, Bindings.CLAVIER), Controles.LIAISON_SANS_NOM,
		"v3.p1: l'ecran affiche un repli nomme, jamais le code")
	h.eq(Bindings.nom_liaison(0, "peripherique_inconnu"), Bindings.NOM_INCONNU,
		"v3.p1: un peripherique inconnu n'a aucune table de noms")

	# LA LIGNE AFFICHEE CITE le nom humain, pas le code.
	var ligne_dash: String = Controles.ligne(Intents.Intention.DASH)
	var code_dash: int = Bindings.liaisons(Intents.Intention.DASH, Bindings.CLAVIER)[0]
	h.eq(ligne_dash.contains(str(code_dash)), false, "v3.p1: la ligne Dash ne cite pas le code")
	h.eq(ligne_dash.contains(Bindings.nom_liaison(code_dash, Bindings.CLAVIER)), true,
		"v3.p1: la ligne Dash cite le nom humain")
