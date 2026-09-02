# v2_menu_pause_entries.gd — ligne menu.pause_entries, capacite F72.
# Cinq entrees identifiees et CINQ TRANSITIONS DEUX A DEUX DIFFERENTES. Le fait que les
# cinq resultats different est asserte sur les TRANSITIONS, pas sur un rendu.
extends RefCounted

const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	h.eq(Menu.ENTREES_PAUSE.size(), 5, "menu.pause: cinq entrees identifiees")
	h.eq(Menu.LIBELLES_PAUSE.size(), 5, "menu.pause: cinq libelles")
	h.eq(Menu.entrees_sans_effet_pause(), 0, "menu.pause: 0 entree sans effet observable")

	var identiques: int = 0
	for i in range(Menu.ENTREES_PAUSE.size()):
		for j in range(i + 1, Menu.ENTREES_PAUSE.size()):
			if not Menu.effets_differents(Menu.effet_pause(Menu.ENTREES_PAUSE[i]), Menu.effet_pause(Menu.ENTREES_PAUSE[j])):
				identiques += 1
	h.eq(identiques, 0, "menu.pause: cinq transitions deux a deux differentes")

	# CONTROLES, OPTIONS et MENU PRINCIPAL : trois ecrans affiches DEUX A DEUX DIFFERENTS.
	var en_partie: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var pause: Dictionary = Sess.mettre_en_pause(en_partie)
	var signatures: Array = []
	for entree in [Menu.Pause.CONTROLES, Menu.Pause.OPTIONS, Menu.Pause.MENU_PRINCIPAL]:
		var r: Dictionary = Shell.activer_pause(pause, entree)
		var contexte: Dictionary = {"selection": 0, "reglages": r["session"]["reglages"], "releve": {}}
		signatures.append(ShellView.signature(ShellView.ecran(int(r["session"]["app"]), contexte)))
	h.eq(signatures.size(), 3, "menu.pause: trois ecrans produits")
	var paires_identiques: int = 0
	for i in range(3):
		for j in range(i + 1, 3):
			if signatures[i] == signatures[j]:
				paires_identiques += 1
	h.eq(paires_identiques, 0, "menu.pause: aucune paire d'ecrans identiques")
	h.ok(signatures[0] != signatures[1], "menu.pause: Controles et Options different")
	h.ok(signatures[1] != signatures[2], "menu.pause: Options et Menu principal different")
	h.ok(signatures[0] != signatures[2], "menu.pause: Controles et Menu principal different")

	# MENU PRINCIPAL ramene a un statut HORS PARTIE.
	var retour: Dictionary = Shell.activer_pause(pause, Menu.Pause.MENU_PRINCIPAL)["session"]
	h.eq(int(retour["app"]), App.Etat.TITRE, "menu.pause: Menu principal ramene au titre")
	h.eq(retour["partie"] == null, true, "menu.pause: la partie est abandonnee")
	h.eq(Sess.statut_de_partie(retour), Sess.AUCUN_STATUT, "menu.pause: statut hors partie")
	h.ok(Sess.statut_de_partie(retour) != State.Statut.EN_COURS, "menu.pause: plus aucune partie en cours")
	h.eq(Sess.ticks_de_partie(retour), 0, "menu.pause: 0 tick de partie apres le retour au titre")
	# --- GATE MUTATION : bornes du menu pause, assertees AUX BORNES ------------------
	h.eq(Menu.libelle_pause(Menu.ENTREES_PAUSE.size()), "",
		"menu.pause: un index egal a la taille est refuse")
	h.eq(Menu.libelle_pause(-1), "", "menu.pause: un index negatif est refuse")
	h.eq(Menu.libelle_pause(Menu.ENTREES_PAUSE.size() - 1), "Menu principal",
		"menu.pause: le dernier index valide est accepte")
	h.eq(Menu.libelle_pause(0), "Reprendre", "menu.pause: le premier index valide est accepte")

	# Le compteur de la pause, exerce sur une liste qui contient une entree sans effet.
	var pause_sans_effet: Array = [{"action": Menu.ACTION_AUCUNE, "etat": App.Etat.PAUSE}]
	var pause_avec_action: Array = [{"action": Menu.ACTION_REPRENDRE, "etat": App.Etat.PAUSE}]
	var pause_autre_ecran: Array = [{"action": Menu.ACTION_AUCUNE, "etat": App.Etat.TITRE}]
	h.eq(Menu.compter_sans_effet(pause_sans_effet, App.Etat.PAUSE), 1,
		"menu.pause: une entree sans effet est comptee")
	h.eq(Menu.compter_sans_effet(pause_avec_action, App.Etat.PAUSE), 0,
		"menu.pause: une entree portant une action n'est pas comptee")
	h.eq(Menu.compter_sans_effet(pause_autre_ecran, App.Etat.PAUSE), 0,
		"menu.pause: une entree menant a un autre ecran n'est pas comptee")
	h.eq(Menu.effets_pause().size(), 5, "menu.pause: cinq effets enumerables")

	# SENS du deplacement de selection : haut et bas ne sont pas interchangeables.
	h.eq(Menu.deplacer(0, 1, 5), 1, "menu.pause: le pas avant avance d'une entree")
	h.eq(Menu.deplacer(1, -1, 5), 0, "menu.pause: le pas arriere recule d'une entree")
	h.eq(Menu.deplacer(4, 1, 5), 0, "menu.pause: le parcours boucle a la derniere entree")
	h.eq(Menu.deplacer(0, -1, 5), 4, "menu.pause: et par le bas aussi")
