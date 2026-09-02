# v2_shell_controls_screen.gd — ligne shell.controls_screen, capacite F68.
# Controles donne un ecran AFFICHE DIFFERENT de l'ecran titre ; le nombre d'entrees sans
# effet observable vaut exactement 0. L'ecran appelant est MEMORISE, jamais suppose.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")


func run(h) -> void:
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}
	var titre: Dictionary = ShellView.ecran(App.Etat.TITRE, contexte)
	var controles: Dictionary = ShellView.ecran(App.Etat.CONTROLES, contexte)
	h.ok(ShellView.signature(titre) != ShellView.signature(controles),
		"shell.controles: l'ecran differe de l'ecran titre")
	h.eq(controles["titre"], Controles.TITRE, "shell.controles: l'ecran porte son titre")
	h.gt(controles["lignes"].size(), 0, "shell.controles: il enumere des lignes")
	h.eq(Menu.entrees_sans_effet_titre(), 0, "shell.controles: 0 entree de menu sans effet observable")

	# L'ACTIVATION depuis le titre y mene reellement.
	var sess: Dictionary = Shell.session_initiale()
	var r: Dictionary = Shell.activer_titre(sess, Menu.Titre.CONTROLES)
	h.eq(int(r["session"]["app"]), App.Etat.CONTROLES, "shell.controles: l'entree y mene")
	h.eq(int(r["session"]["appelant"]), App.Etat.TITRE, "shell.controles: l'appelant est memorise")
	h.eq(r["sortie"], false, "shell.controles: elle ne termine pas l'application")

	# LE RETOUR revient a l'appelant MEMORISE, jamais a un ecran suppose.
	h.eq(Controles.retour(App.Etat.TITRE), App.Etat.TITRE, "shell.controles: retour au titre")
	h.eq(Controles.retour(App.Etat.PAUSE), App.Etat.PAUSE, "shell.controles: retour a la pause")
	h.eq(Controles.retour(99), App.Etat.TITRE, "shell.controles: un appelant invalide retombe au titre")

	# ENUMERATION PAR INTENTION ET PAR PERIPHERIQUE.
	h.eq(Controles.lignes().size(), Controles.LIBELLES.size(), "shell.controles: une ligne par intention")
	var vides: int = 0
	for l in Controles.lignes():
		if String(l).strip_edges() == "":
			vides += 1
	h.eq(vides, 0, "shell.controles: aucune ligne vide")
