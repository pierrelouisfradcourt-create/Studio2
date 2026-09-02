# v2_menu_title_entries.test.gd — ligne menu.title_entries, capacite F66.
# Le menu titre est une DONNEE enumerable : une entree est une ligne de liste, jamais un
# libelle dessine — c'est ce qui rend COMPTABLE le nombre d'entrees sans effet.
extends RefCounted

const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")


func run(h) -> void:
	h.eq(Menu.ENTREES_TITRE.size(), 4, "menu.titre: quatre entrees identifiees")
	h.eq(Menu.LIBELLES_TITRE.size(), 4, "menu.titre: quatre libelles")
	h.eq(Menu.libelle_titre(Menu.Titre.JOUER), "Jouer", "menu.titre: libelle Jouer")
	h.eq(Menu.libelle_titre(Menu.Titre.QUITTER), "Quitter", "menu.titre: libelle Quitter")
	h.eq(Menu.libelle_titre(9), "", "menu.titre: une entree inconnue n'a pas de libelle")

	# LE COMPTAGE QUI FAIT FOI : aucune entree sans effet observable.
	h.eq(Menu.entrees_sans_effet_titre(), 0, "menu.titre: 0 entree sans effet observable")

	# Les quatre effets sont DEUX A DEUX DIFFERENTS.
	var identiques: int = 0
	for i in range(Menu.ENTREES_TITRE.size()):
		for j in range(i + 1, Menu.ENTREES_TITRE.size()):
			if not Menu.effets_differents(Menu.effet_titre(Menu.ENTREES_TITRE[i]), Menu.effet_titre(Menu.ENTREES_TITRE[j])):
				identiques += 1
	h.eq(identiques, 0, "menu.titre: quatre effets deux a deux differents")

	h.eq(Menu.effet_titre(Menu.Titre.JOUER)["action"], Menu.ACTION_NOUVELLE_PARTIE, "menu.titre: Jouer lance une partie")
	h.eq(Menu.effet_titre(Menu.Titre.JOUER)["etat"], App.Etat.PARTIE, "menu.titre: Jouer mene a la partie")
	h.eq(Menu.effet_titre(Menu.Titre.CONTROLES)["etat"], App.Etat.CONTROLES, "menu.titre: Controles mene a son ecran")
	h.eq(Menu.effet_titre(Menu.Titre.OPTIONS)["etat"], App.Etat.OPTIONS, "menu.titre: Options mene a son ecran")
	h.eq(Menu.effet_titre(Menu.Titre.QUITTER)["action"], Menu.ACTION_QUITTER, "menu.titre: Quitter demande la sortie")

	# SELECTION : le parcours boucle, il n'existe aucune selection hors liste.
	h.eq(Menu.deplacer(0, 1, 4), 1, "menu.titre: selection suivante")
	h.eq(Menu.deplacer(3, 1, 4), 0, "menu.titre: la selection boucle par le haut")
	h.eq(Menu.deplacer(0, -1, 4), 3, "menu.titre: la selection boucle par le bas")
	h.eq(Menu.deplacer(0, 1, 0), 0, "menu.titre: une liste vide ne deborde pas")
	# --- GATE MUTATION : bornes assertees AUX BORNES, jamais dans le confort ---------
	# ge->gt@L36 : un index EGAL a la taille doit etre refuse, pas seulement un index
	# tres grand. or->and@L36 : un index NEGATIF doit l'etre aussi.
	h.eq(Menu.libelle_titre(Menu.ENTREES_TITRE.size()), "",
		"menu.titre: un index egal a la taille est refuse")
	h.eq(Menu.libelle_titre(-1), "", "menu.titre: un index negatif est refuse")
	h.eq(Menu.libelle_titre(Menu.ENTREES_TITRE.size() - 1), "Quitter",
		"menu.titre: le dernier index valide est accepte")
	h.eq(Menu.libelle_titre(0), "Jouer", "menu.titre: le premier index valide est accepte")

	# le->lt@L50 : une taille de liste NULLE est le cas de bord du deplacement.
	h.eq(Menu.deplacer(0, 1, 0), 0, "menu.titre: taille nulle, aucune selection")
	h.eq(Menu.deplacer(0, 1, 1), 0, "menu.titre: taille 1, la selection ne bouge pas")
	h.eq(Menu.deplacer(0, -1, 1), 0, "menu.titre: taille 1, dans l'autre sens non plus")

	# COMPTEUR SANS EFFET : exerce sur une liste QUI CONTIENT une entree sans effet.
	# Sans ce releve, le corps de la boucle n'est jamais atteint et ni le SENS de son
	# increment ni les deux membres de sa condition ne sont prouves.
	var sans_effet: Array = [{"action": Menu.ACTION_AUCUNE, "etat": App.Etat.TITRE}]
	var avec_effet: Array = [{"action": Menu.ACTION_QUITTER, "etat": App.Etat.TITRE}]
	var autre_ecran: Array = [{"action": Menu.ACTION_AUCUNE, "etat": App.Etat.PAUSE}]
	h.eq(Menu.compter_sans_effet(sans_effet, App.Etat.TITRE), 1,
		"menu.titre: une entree sans effet est comptee UNE fois")
	h.eq(Menu.compter_sans_effet(avec_effet, App.Etat.TITRE), 0,
		"menu.titre: une entree avec action n'est pas comptee")
	h.eq(Menu.compter_sans_effet(autre_ecran, App.Etat.TITRE), 0,
		"menu.titre: une entree menant a un AUTRE ecran n'est pas comptee")
	h.eq(Menu.compter_sans_effet(sans_effet + sans_effet, App.Etat.TITRE), 2,
		"menu.titre: le compteur croit strictement avec le nombre d'entrees sans effet")
	h.eq(Menu.compter_sans_effet([], App.Etat.TITRE), 0, "menu.titre: liste vide, compte nul")
	h.eq(Menu.effets_titre().size(), 4, "menu.titre: quatre effets enumerables")
