# v2_shell_title_entry_effects.gd — ligne shell.title_entry_effects, capacite F67.
# La coquille FAIT EXISTER LES EFFETS : Jouer met la partie en cours, Controles et
# Options amenent chacun a un ecran different, Quitter termine l'application avec un
# code de sortie nul. Le defaut vise nommement est « Quitter inerte ».
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	var sess: Dictionary = Shell.session_initiale()
	var contexte: Dictionary = {"selection": 0, "reglages": {}, "releve": {}}

	# JOUER : le statut vaut EN COURS.
	var jouer: Dictionary = Shell.activer_titre(sess, Menu.Titre.JOUER)
	h.eq(jouer["session"]["partie"].statut, State.Statut.EN_COURS, "shell.effets: Jouer met la partie en cours")
	h.eq(int(jouer["session"]["app"]), App.Etat.PARTIE, "shell.effets: l'application passe en partie")

	# CONTROLES puis OPTIONS : deux ecrans differents, et differents du titre.
	var c: Dictionary = Shell.activer_titre(sess, Menu.Titre.CONTROLES)
	var o: Dictionary = Shell.activer_titre(sess, Menu.Titre.OPTIONS)
	var s_titre: String = ShellView.signature(ShellView.ecran(App.Etat.TITRE, contexte))
	var s_c: String = ShellView.signature(ShellView.ecran(int(c["session"]["app"]), contexte))
	var s_o: String = ShellView.signature(ShellView.ecran(int(o["session"]["app"]), contexte))
	h.ok(s_c != s_titre, "shell.effets: Controles donne un ecran different du titre")
	h.ok(s_o != s_titre, "shell.effets: Options donne un ecran different du titre")
	h.ok(s_o != s_c, "shell.effets: Options differe des deux precedents")

	# QUITTER : l'effet EXISTE — la demande de sortie est observable, et le code est nul.
	var q: Dictionary = Shell.activer_titre(sess, Menu.Titre.QUITTER)
	h.eq(q["sortie"], true, "shell.effets: Quitter demande la sortie")
	h.eq(Shell.CODE_SORTIE, 0, "shell.effets: le code de sortie est nul")
	var inertes: int = 0
	for entree in Menu.ENTREES_TITRE:
		var r: Dictionary = Shell.activer_titre(sess, entree)
		var change: bool = (r["sortie"]
			or int(r["session"]["app"]) != int(sess["app"])
			or r["session"]["partie"] != sess["partie"])
		if not change:
			inertes += 1
	h.eq(inertes, 0, "shell.effets: 0 entree inerte parmi les quatre")

	# CONTRE-EPREUVE : le detecteur d'inertie FONCTIONNE — une entree inconnue est inerte.
	var inconnue: Dictionary = Shell.activer_titre(sess, 99)
	h.eq(inconnue["sortie"], false, "shell.effets: une entree inconnue ne sort pas")
	h.eq(int(inconnue["session"]["app"]), int(sess["app"]), "shell.effets: et ne change pas d'ecran")
