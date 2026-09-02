# v3_p5_end_of_game_choices.gd — CAUSE RACINE P5.
#
# DEFAUT MESURE (playtest Pierre) : arrive a la fin du dernier niveau, le joueur restait
# BLOQUE. La logique pure avait pourtant DEJA tout — App.Etat.FIN, vers_partie,
# vers_titre, et session.carte_terminee qui traite SUITE_CATALOGUE_TERMINE. Le defaut
# etait dans le CABLAGE RUNTIME : Etat.FIN n'etait traite qu'a UN endroit
# (app_shell.gd:107) et end_screen.gd ne rendait qu'un texte d'issue, SANS AUCUN CHOIX.
#
# Second cas de la MEME cause, trouve en corrigeant : une partie terminee SUR PLACE
# (victoire ou defaite au milieu du catalogue) restait dans App.Etat.PARTIE, ou aucune
# intention n'est routee vers la coquille — impasse identique.
#
# CE QUE CETTE PREUVE MESURE : que la fin OFFRE des suites (0 choix sans effet), que
# chacune MENE quelque part, et qu'aucun etat terminal n'est un cul-de-sac.
extends RefCounted

const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")


func run(h) -> void:
	# --- L'ECRAN DE FIN OFFRE DES SUITES, il ne les annonce pas. ---
	h.eq(EndScreen.ENTREES.size(), 2, "v3.p5: deux suites offertes")
	h.eq(EndScreen.choix_sans_effet(), 0, "v3.p5: 0 choix sans effet observable")
	h.ok(Menu.effets_differents(EndScreen.effet(EndScreen.Choix.REJOUER),
		EndScreen.effet(EndScreen.Choix.MENU_PRINCIPAL)),
		"v3.p5: les deux suites menent a deux endroits differents")
	h.eq(EndScreen.libelle(EndScreen.Choix.REJOUER), "Rejouer", "v3.p5: la relance est nommee")
	h.eq(EndScreen.libelle(-1), "", "v3.p5: un choix hors bornes n'a pas de libelle")
	h.eq(EndScreen.libelle(EndScreen.ENTREES.size()), "", "v3.p5: borne haute egalement gardee")
	h.eq(EndScreen.effet(99)["action"], Menu.ACTION_AUCUNE, "v3.p5: un choix inconnu ne fait rien")

	# LA SELECTION EST MARQUEE et se deplace : sans marque, deux choix seraient
	# indiscernables a l'ecran.
	h.ok(EndScreen.lignes(0)[0] != EndScreen.lignes(1)[0], "v3.p5: la selection est visible")
	h.eq(EndScreen.lignes(0).size(), 2, "v3.p5: une ligne par suite")

	# --- LE CATALOGUE EPUISE MENE A L'ETAT FINAL, selection remise a zero. ---
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	h.eq(int(sess["app"]), App.Etat.PARTIE, "v3.p5: une partie est en cours")
	var partie = sess["partie"]
	partie.niveau = Shell.nb_niveaux()
	partie.consommees = partie.total_pose
	sess["partie"] = partie
	h.eq(Progression.suite(partie, Shell.nb_niveaux()), Progression.SUITE_CATALOGUE_TERMINE,
		"v3.p5: la logique pure sait que le catalogue est epuise")
	var final: Dictionary = Shell.enchainer_niveau(sess)
	h.eq(int(final["app"]), App.Etat.FIN, "v3.p5: le dernier niveau mene a l'etat final")
	h.eq(int(final["selection"]), 0, "v3.p5: la selection du menu de fin part a zero")
	h.eq(final["partie"].statut, State.Statut.GAGNE, "v3.p5: la partie est gagnee")

	# --- ET DE L'ETAT FINAL, ON REPART. C'est ce qui manquait. ---
	var bas: Dictionary = Shell.appliquer_intention(final, Intents.Intention.BAS)
	h.eq(int(bas["session"]["selection"]), 1, "v3.p5: la selection se deplace a la fin")
	var haut: Dictionary = Shell.appliquer_intention(bas["session"], Intents.Intention.HAUT)
	h.eq(int(haut["session"]["selection"]), 0, "v3.p5: elle revient")

	var rejoue: Dictionary = Shell.appliquer_intention(final, Intents.Intention.VALIDER)
	h.eq(int(rejoue["session"]["app"]), App.Etat.PARTIE, "v3.p5: Rejouer relance une partie")
	h.eq(rejoue["session"]["partie"].ticks, 0, "v3.p5: la partie relancee repart a zero tick")
	h.eq(rejoue["session"]["partie"].niveau, State.PREMIER_NIVEAU, "v3.p5: et au premier niveau")
	h.eq(rejoue["sortie"], false, "v3.p5: Rejouer ne quitte pas l'application")

	var vers_menu: Dictionary = Shell.appliquer_intention(bas["session"], Intents.Intention.VALIDER)
	h.eq(int(vers_menu["session"]["app"]), App.Etat.TITRE, "v3.p5: Menu principal ramene au titre")
	h.eq(vers_menu["session"]["partie"], null, "v3.p5: la partie est abandonnee")
	var retour: Dictionary = Shell.appliquer_intention(final, Intents.Intention.RETOUR)
	h.eq(int(retour["session"]["app"]), App.Etat.TITRE, "v3.p5: Retour ramene au titre")
	h.eq(retour["sortie"], false, "v3.p5: Retour ne quitte pas l'application en silence")

	# --- AUCUN ETAT TERMINAL N'EST UN CUL-DE-SAC (second cas de la meme cause). ---
	# Une partie PERDUE au milieu du catalogue passe elle aussi a l'ecran final.
	var perdue: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	perdue["partie"].vies = 0
	Status.appliquer(perdue["partie"])
	h.eq(perdue["partie"].statut, State.Statut.PERDU, "v3.p5: la partie est perdue")
	h.eq(int(perdue["app"]), App.Etat.PARTIE, "v3.p5: avant cablage, l'etat restait PARTIE")
	var apres_defaite: Dictionary = Shell.terminer_partie(perdue)
	h.eq(int(apres_defaite["app"]), App.Etat.FIN, "v3.p5: une defaite mene aussi a l'ecran final")
	var relance: Dictionary = Shell.appliquer_intention(apres_defaite, Intents.Intention.VALIDER)
	h.eq(int(relance["session"]["app"]), App.Etat.PARTIE, "v3.p5: on repart d'une defaite")

	# UNE PARTIE EN COURS n'est PAS terminee de force : la transition a une condition.
	var en_cours: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	h.eq(int(Shell.terminer_partie(en_cours)["app"]), App.Etat.PARTIE,
		"v3.p5: une partie en cours n'est pas terminee de force")
	h.eq(int(Shell.terminer_partie(Shell.session_initiale())["app"]), App.Etat.TITRE,
		"v3.p5: sans partie, rien a terminer")

	# --- L'ECRAN AFFICHE LES SUITES, et reste distinct des autres ecrans. ---
	var releve: Dictionary = {"statut": State.Statut.GAGNE, "score": 1234}
	var recap: String = EndScreen.recap(releve, 0)
	h.ok(recap.contains(EndScreen.libelle(EndScreen.Choix.REJOUER)), "v3.p5: le recap offre Rejouer")
	h.ok(recap.contains(EndScreen.libelle(EndScreen.Choix.MENU_PRINCIPAL)),
		"v3.p5: le recap offre Menu principal")
	h.ok(recap.contains("1234"), "v3.p5: le score final est toujours affiche")
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": releve}
	var ecran: Dictionary = ShellView.ecran(App.Etat.FIN, contexte)
	h.gt(ecran["lignes"].size(), 2, "v3.p5: l'ecran de fin porte ses choix")
	h.eq(ShellView.paires_identiques(contexte), 0, "v3.p5: aucun ecran n'en double un autre")
