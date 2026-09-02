# v2_shell_manual_path_complete.gd — ligne shell.manual_path_complete, capacite F115.
# PROVENANCE, PAS PREUVE. Volet MACHINE : chaque etape du chemin produit est ATTEIGNABLE
# par le SEUL canal d'entree public, sans console de debug ni bot — le nombre d'etapes
# exigeant un outil vaut exactement 0.
# Volet HUMAIN : qu'une personne parcoure le chemin seule n'est tranche par aucun oracle
# — besoin remonte en fog HumanGate.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")


func run(h) -> void:
	h.eq(Shell.ETAPES.size(), 7, "shell.chemin: sept etapes declarees")
	h.eq(Shell.etapes_exigeant_un_outil(), 0, "shell.chemin: 0 etape exigeant un outil")
	var sans_intention: int = 0
	for e in Shell.ETAPES:
		if not Intents.valide(Shell.intention_de_l_etape(String(e))):
			sans_intention += 1
	h.eq(sans_intention, 0, "shell.chemin: chaque etape a une intention du vocabulaire ferme")
	h.eq(Shell.intention_de_l_etape("etape_inconnue"), Intents.Intention.AUCUNE,
		"shell.chemin: une etape inconnue n'a aucune intention")

	# LE CHEMIN EST PARCOURU par le seul canal d'entree public.
	var sess: Dictionary = Shell.session_initiale()
	h.eq(int(sess["app"]), App.Etat.TITRE, "shell.chemin: etape 1 — ecran titre")
	sess = Shell.appliquer_intention(sess, Intents.Intention.VALIDER)["session"]
	h.eq(int(sess["app"]), App.Etat.PARTIE, "shell.chemin: etape 2 — lancement")
	sess = Shell.appliquer_intention(sess, Intents.Intention.PAUSE)["session"]
	h.eq(int(sess["app"]), App.Etat.PAUSE, "shell.chemin: etape 3 — pause")
	sess = Shell.appliquer_intention(sess, Intents.Intention.VALIDER)["session"]
	h.eq(int(sess["app"]), App.Etat.PARTIE, "shell.chemin: etape 4 — reprise")

	# ETAPE 5 — passage au niveau suivant, dans la MEME execution.
	var jeu = sess["partie"]
	jeu.consommees = jeu.total_pose
	sess["partie"] = jeu
	sess = Shell.enchainer_niveau(sess)
	h.eq(sess["partie"].niveau, 2, "shell.chemin: etape 5 — niveau suivant atteint")
	h.eq(int(sess["app"]), App.Etat.PARTIE, "shell.chemin: sans relance de l'application")

	# ETAPE 6 — vider TOUTES les cartes restantes mene a l ETAT FINAL EXPLICITE, quel
	# que soit le nombre de cartes du catalogue : le chemin produit ne suppose pas deux
	# cartes, il suit le catalogue.
	var garde: int = 0
	while int(sess["app"]) == App.Etat.PARTIE and garde < 32:
		var courant = sess["partie"]
		courant.consommees = courant.total_pose
		sess["partie"] = courant
		sess = Shell.enchainer_niveau(sess)
		garde += 1
	h.eq(int(sess["app"]), App.Etat.FIN, "shell.chemin: etape 6 — fin de partie")
	h.lt(garde, 32, "shell.chemin: le catalogue s epuise sans boucler indefiniment")
	h.eq(sess["partie"].statut, State.Statut.GAGNE, "shell.chemin: statut final explicite")

	# ETAPE 7 — relance, par le meme canal.
	sess = Shell.appliquer_intention(sess, Intents.Intention.VALIDER)["session"]
	h.eq(int(sess["app"]), App.Etat.PARTIE, "shell.chemin: etape 7 — relance")
	h.eq(sess["partie"].ticks, 0, "shell.chemin: la relance repart d une partie neuve")
