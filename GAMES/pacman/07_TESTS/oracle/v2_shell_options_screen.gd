# v2_shell_options_screen.gd — ligne shell.options_screen, capacite F69.
# Options donne un ecran DIFFERENT des deux precedents ; le nombre d'entrees sans effet
# observable vaut exactement 0.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")


func run(h) -> void:
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}
	var titre: Dictionary = ShellView.ecran(App.Etat.TITRE, contexte)
	var controles: Dictionary = ShellView.ecran(App.Etat.CONTROLES, contexte)
	var options: Dictionary = ShellView.ecran(App.Etat.OPTIONS, contexte)
	h.ok(ShellView.signature(options) != ShellView.signature(titre), "shell.options: different du titre")
	h.ok(ShellView.signature(options) != ShellView.signature(controles), "shell.options: different des controles")
	h.eq(options["titre"], Options.TITRE, "shell.options: l'ecran porte son titre")
	# TRIAGE V6 : DECISION_OBSOLETE. V5 avait deja porte le compte a « entrees + 1 »
	# (l'explication du mode) ; V6 ajoute la mention qui separe MODE et DASH, deux reglages
	# distincts que le joueur confondait. Le compte est desormais adosse au nombre DECLARE
	# de lignes de lecture, jamais a un nombre ecrit a la main — et reste une egalite
	# stricte, jamais un `>=`.
	h.eq(options["lignes"].size(), Options.ENTREES.size() + Options.LIGNES_DE_LECTURE,
		"shell.options: une ligne par reglage, plus les lignes de lecture declarees")

	# CHAQUE ENTREE a un effet observable sur les reglages.
	h.eq(Options.entrees_sans_effet({}), 0, "shell.options: 0 entree sans effet")
	var r0: Dictionary = Reglages.initial()
	var apres_mode: Dictionary = Options.activer(Options.Entree.MODE, r0)
	h.ok(apres_mode["mode"] != r0["mode"], "shell.options: le mode change")
	var apres_dash: Dictionary = Options.activer(Options.Entree.DASH, r0)
	h.ok(apres_dash["dash_actif"] != r0["dash_actif"], "shell.options: l'activation du dash change")
	h.eq(Options.activer(99, r0), Reglages.normaliser(r0), "shell.options: une entree inconnue ne change rien")

	# LE CHANGEMENT est REPERCUTE dans l'etat expose de la partie.
	var sess: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	var modifie: Dictionary = Sess.appliquer_reglages(sess, apres_dash)
	h.eq(modifie["partie"].dash_actif, apres_dash["dash_actif"], "shell.options: la partie suit le reglage")
	h.eq(modifie["reglages"]["dash_actif"], apres_dash["dash_actif"], "shell.options: la session aussi")

	# LES VALEURS AFFICHEES suivent les reglages.
	# TRIAGE V5 : DECISION_OBSOLETE. Afficher « NORMAL » etait montrer l'identifiant interne
	# de l'enum au joueur — la cause racine P1 elle-meme. La valeur affichee est desormais
	# le LIBELLE ; l'identifiant reste lisible par `Reglages.nom`, et le releve de
	# debogage continue de le porter (v2_probe_exposes_app_state, INVARIANT non touche).
	h.eq(Options.valeur_lisible(Options.Entree.MODE, r0), "Arcade", "shell.options: valeur du mode affichee")
	h.ok(Options.valeur_lisible(Options.Entree.MODE, r0) != Reglages.nom(r0["mode"]),
		"shell.options: le joueur ne lit pas l'identifiant interne")
	h.eq(Options.valeur_lisible(Options.Entree.DASH, r0), Options.ACTIF, "shell.options: valeur du dash affichee")
	h.eq(Options.valeur_lisible(99, r0), "", "shell.options: une entree inconnue n'affiche rien")
	h.eq(Options.retour(App.Etat.PAUSE), App.Etat.PAUSE, "shell.options: retour a l'appelant memorise")
