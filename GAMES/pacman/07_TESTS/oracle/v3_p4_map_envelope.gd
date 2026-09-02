# v3_p4_map_envelope.gd — CAUSE RACINE P4.
#
# DEFAUT MESURE (playtest Pierre) : la carte 2 etait plus petite ET collee en haut a
# gauche. Cause a la ligne pres : `maze_view.gd:12`, `const COTE_CASE: int = 20`. La
# taille de case etait une CONSTANTE : la carte de reference (28x36) remplissait la
# fenetre par coincidence, et toute autre carte occupait un coin.
#
# CE QUE CETTE PREUVE MESURE — et l'invariant demande est « MEME ENVELOPPE POUR N
# CARTES », pas « pour deux » : sur les cartes du catalogue ET sur des cartes de forme
# volontairement extreme (tres large, tres haute, minuscule), (1) la grille tient dans
# l'enveloppe, debordement exactement 0 ; (2) la taille de case est MAXIMALE — l'agrandir
# d'un pixel ferait deborder ; (3) le centrage est equilibre, marges egales a un pixel
# pres ; (4) l'enveloppe ne depend PAS de la carte dessinee.
extends RefCounted

const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")


# Carte SYNTHETIQUE d'une forme donnee. Elle n'a pas a etre jouable : cette preuve porte
# sur la GEOMETRIE D'ECRAN, qui ne consulte que la largeur et la hauteur.
func _carte(largeur: int, hauteur: int):
	var plan: Array = []
	for _y in range(hauteur):
		var ligne := ""
		for _x in range(largeur):
			ligne += "#"
		plan.append(ligne)
	return MazeClass.depuis_descripteur({"id": "synthetique", "nom": "synthetique", "plan": plan})


func run(h) -> void:
	var lenv: int = Boot.largeur_fenetre()
	var henv: int = Boot.hauteur_fenetre()
	h.gt(lenv, 0, "v3.p4: l'enveloppe a une largeur")
	h.gt(henv, 0, "v3.p4: l'enveloppe a une hauteur")

	# L'ENVELOPPE EST LA MEME POUR TOUTES LES CARTES : elle est definie par la carte de
	# reference, jamais par celle qu'on dessine. C'etait le coeur du defaut.
	var reference = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
	h.eq(lenv, MazeView.largeur_enveloppe(reference), "v3.p4: l'enveloppe suit la carte de reference")
	h.eq(henv, MazeView.hauteur_enveloppe(reference), "v3.p4: idem en hauteur")
	h.eq(MazeView.cote_case(reference, lenv, henv), MazeView.COTE_CASE,
		"v3.p4: la carte de reference garde sa taille de case (non-regression)")
	h.eq(MazeView.origine(reference, lenv, henv), Vector2.ZERO,
		"v3.p4: la carte de reference remplit exactement l'enveloppe")

	# LES CARTES A EPROUVER : celles du catalogue, plus quatre formes extremes. « N
	# cartes », pas deux.
	var cartes: Array = []
	for i in range(ContentV2.nb_niveaux()):
		cartes.append(MazeClass.depuis_descripteur(ContentV2.descripteur(i)))
	h.gt(cartes.size(), 1, "v3.p4: le catalogue porte plusieurs cartes")
	cartes.append(_carte(21, 24))    # la carte 2 du defaut mesure
	cartes.append(_carte(60, 8))     # tres large
	cartes.append(_carte(8, 60))     # tres haute
	cartes.append(_carte(3, 3))      # minuscule
	cartes.append(_carte(200, 200))  # plus grande que l'enveloppe

	var debordements: int = 0
	var non_maximales: int = 0
	var mal_centrees: int = 0
	var trop_petites: int = 0
	for c in cartes:
		var cote: int = MazeView.cote_case(c, lenv, henv)
		# (1) TIENT DANS L'ENVELOPPE.
		if MazeView.debordement(c, lenv, henv) != Vector2i(0, 0):
			debordements += 1
		# (2) TAILLE MAXIMALE : un pixel de plus deborderait sur au moins un axe.
		if (c.LARGEUR * (cote + 1) <= lenv) and (c.HAUTEUR * (cote + 1) <= henv):
			non_maximales += 1
		# (3) CENTRAGE : les deux marges sont egales a un pixel pres.
		var orig: Vector2 = MazeView.origine(c, lenv, henv)
		var marge_droite: float = float(lenv) - orig.x - float(c.LARGEUR * cote)
		var marge_bas: float = float(henv) - orig.y - float(c.HAUTEUR * cote)
		if absf(marge_droite - orig.x) > 1.0 or absf(marge_bas - orig.y) > 1.0:
			mal_centrees += 1
		if cote < MazeView.COTE_CASE_MIN:
			trop_petites += 1
	h.eq(debordements, 0, "v3.p4: 0 carte ne deborde de l'enveloppe")
	h.eq(non_maximales, 0, "v3.p4: 0 carte dessinee plus petite qu'elle ne pourrait")
	h.eq(mal_centrees, 0, "v3.p4: 0 carte ancree hors du centre")
	h.eq(trop_petites, 0, "v3.p4: 0 carte reduite au point de disparaitre")
	h.eq(Boot.carte_tient_dans_l_enveloppe(cartes[1]), true,
		"v3.p4: la deuxieme carte du catalogue tient dans la meme fenetre")

	# LA CARTE 2 DU DEFAUT MESURE : plus petite que la reference, elle est desormais
	# AGRANDIE et CENTREE au lieu d'etre laissee a 20 pixels dans un coin.
	var carte2 = _carte(21, 24)
	var cote2: int = MazeView.cote_case(carte2, lenv, henv)
	h.gt(cote2, MazeView.COTE_CASE, "v3.p4: la carte 2 est dessinee plus grand qu'avant")
	h.gt(int(MazeView.origine(carte2, lenv, henv).x), 0, "v3.p4: la carte 2 n'est plus collee a gauche")

	# UNE CARTE DEGENERE ne fait pas exploser la geometrie : elle est REFUSEE en douceur.
	var vide = MazeClass.depuis_descripteur({"id": "vide", "nom": "vide", "plan": []})
	h.eq(MazeView.cote_case(vide, lenv, henv), MazeView.COTE_CASE_MIN,
		"v3.p4: une carte sans dimension retombe sur la taille minimale declaree")

	# L'ECHELLE DES ENTITES SUIT la taille de case : sur une carte dessinee plus grand,
	# le joueur grandit avec elle au lieu de flotter dans sa case.
	h.eq(MazeView.echelle(MazeView.COTE_CASE), 1.0, "v3.p4: echelle de reference")
	h.gt(int(MazeView.echelle(cote2) * 1000.0), 1000, "v3.p4: les entites grandissent avec la case")

	# LES DEUX REPERES coincident dans le cadre de reference : une seule implementation.
	h.eq(MazeView.rect_case(Vector2i(2, 3)),
		MazeView.rect_case_dans(Vector2i(2, 3), MazeView.COTE_CASE, Vector2.ZERO),
		"v3.p4: le repere de reference est le cas particulier du repere general")
	h.eq(MazeView.centre_case(Vector2i(2, 3)),
		MazeView.centre_case_dans(Vector2i(2, 3), MazeView.COTE_CASE, Vector2.ZERO),
		"v3.p4: idem pour le centre de case")
