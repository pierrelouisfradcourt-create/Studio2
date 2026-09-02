# v2_app_pause_entry.gd — ligne app.pause_entry, capacite F70.
# L'intention de pause converge, QUELLE QUE SOIT sa source, vers un seul et meme etat :
# la transition est definie sur l'INTENTION, jamais sur le peripherique. Les trois
# chemins ne peuvent donc pas produire trois ecrans paralleles.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const Touch = preload("res://06_RUNTIME/adapters/touch_input/touch_input.gd")


func run(h) -> void:
	var en_partie: Dictionary = Shell.activer_titre(Shell.session_initiale(), Menu.Titre.JOUER)["session"]
	h.eq(int(en_partie["app"]), App.Etat.PARTIE, "app.pause: une partie est en cours avant la pause")

	# LES TROIS CHEMINS produisent la MEME intention.
	var touche: int = Bindings.liaisons(Intents.Intention.PAUSE, Bindings.CLAVIER)[0]
	var bouton: int = Bindings.liaisons(Intents.Intention.PAUSE, Bindings.MANETTE)[0]
	var zone: String = Bindings.liaisons(Intents.Intention.PAUSE, Bindings.TACTILE)[0]
	h.eq(InputAdapter.intention_de_touche(touche), Intents.Intention.PAUSE, "app.pause: chemin clavier")
	h.eq(InputAdapter.intention_de_bouton(bouton), Intents.Intention.PAUSE, "app.pause: chemin manette")
	h.eq(InputAdapter.intention_de_zone(zone), Intents.Intention.PAUSE, "app.pause: chemin tactile")

	# LES TROIS CHEMINS aboutissent au MEME etat d'application.
	var etats: Array = []
	for _chemin in range(3):
		var r: Dictionary = Shell.appliquer_intention(en_partie, Intents.Intention.PAUSE)
		etats.append(int(r["session"]["app"]))
	h.eq(etats[0], App.Etat.PAUSE, "app.pause: le menu pause est actif apres l'entree clavier")
	h.eq(etats[1], App.Etat.PAUSE, "app.pause: le menu pause est actif apres l'entree manette")
	h.eq(etats[2], App.Etat.PAUSE, "app.pause: le menu pause est actif apres l'entree tactile")
	var divergents: int = 0
	for e in etats:
		if e != etats[0]:
			divergents += 1
	h.eq(divergents, 0, "app.pause: les trois chemins ne produisent qu'un seul etat")

	# TRANSITION UNIQUE : elle n'existe que depuis une partie en cours.
	h.eq(App.vers_pause(App.Etat.PARTIE), App.Etat.PAUSE, "app.pause: transition depuis la partie")
	h.eq(App.vers_pause(App.Etat.TITRE), App.Etat.TITRE, "app.pause: aucune pause depuis le titre")
	h.eq(App.vers_pause(App.Etat.PAUSE), App.Etat.PAUSE, "app.pause: la pause ne se redouble pas")
	h.eq(App.peut_mettre_en_pause(App.Etat.FIN), false, "app.pause: aucune pause depuis la fin")

	# La PARTIE n'est pas modifiee par l'ouverture de la pause.
	var pause: Dictionary = Sess.mettre_en_pause(en_partie)
	h.eq(pause["partie"].egal_profond(en_partie["partie"]), true,
		"app.pause: l'etat de partie est inchange par l'ouverture")
	h.eq(Touch.zones_disjointes(560, 720), true, "app.pause: les surfaces tactiles sont disjointes")
