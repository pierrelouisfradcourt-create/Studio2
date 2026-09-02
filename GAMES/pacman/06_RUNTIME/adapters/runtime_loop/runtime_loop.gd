# runtime_loop.gd — script de la scene principale (res://main.tscn) et cadenceur
# (lignes runtime.boot_window, runtime.tick_cadence, runtime.title_boot_no_game,
# runtime.pause_freeze, core.boot, core.exit).
#
# SEUL endroit du jeu ou une horloge de plateforme est lue. Il ASSEMBLE des briques
# deja prouvees : il ne contient AUCUNE regle de jeu. La logique pure de 05_SYSTEMS ne
# connait rien de ce fichier — la dependance va a sens unique.
#
# V2 : le temps du moteur n'est converti en appels au tick pur QUE lorsque l'etat
# d'application l'autorise (app_state.tick_autorise). Pendant la pause, AUCUN tick n'est
# execute : l'etat releve a l'ouverture et l'etat releve N ticks plus tard sont le MEME
# etat, et non deux etats voisins. La pause gele donc par ABSENCE D'APPEL.
extends Node2D

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Touch = preload("res://06_RUNTIME/adapters/touch_input/touch_input.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const Banner = preload("res://06_RUNTIME/adapters/presentation/state_banner.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

# Code de sortie observable du processus.
const CODE_SORTIE: int = 0

var _session: Dictionary = {}
var _accum_ms: float = 0.0
var _demande: Vector2i = Maze.AUCUNE
var _dash_demande: bool = false
var _hud: Label
var _banniere: Label
var _fin: Label
var _menu: Label


# --- Cadenceur PUR (ligne runtime.tick_cadence) : convertit le temps du moteur en 0 ou
# 1 tick, SANS rattrapage. `gele` porte l'unique autorite consultee : app_state.
# Static : testable sans lancer de scene.
static func avancer(accumulateur: float, delta_ms: float, periode_ms: float, gele: bool) -> Dictionary:
	if gele:
		return {"accumulateur": 0.0, "ticks": 0}
	var a: float = accumulateur + delta_ms
	if a < periode_ms:
		return {"accumulateur": a, "ticks": 0}
	# Un tick au plus par trame : aucun rattrapage, donc aucune acceleration fantome.
	return {"accumulateur": a - periode_ms, "ticks": 1}


# Le tick de partie est-il autorise ? UNIQUE autorite : app_state. C'est ce predicat, et
# lui seul, qui distingue « aucune partie n'avance » de « un menu masque une partie ».
static func tick_autorise(sess: Dictionary) -> bool:
	if sess.get("partie", null) == null:
		return false
	if not App.tick_autorise(int(sess["app"])):
		return false
	return sess["partie"].statut == State.Statut.EN_COURS


# --- UNE SEULE SURFACE DE TEXTE PAR ETAT (V4, cause racine P2) --------------------
# Second volet du defaut « ecran de fin illisible » : a l'etat FIN, DEUX blocs de texte
# etaient rendus au MEME endroit — le recap de fin (_fin, a hauteur/2 - 48) et l'ecran de
# coquille FIN (_menu, a hauteur/2 - 120). Les deux se chevauchaient. Ces deux predicats
# sont l'unique autorite d'affichage, et ils sont EXCLUSIFS par construction.
static func surface_de_fin(app_etat: int) -> bool:
	return app_etat == App.Etat.FIN


# Le menu de coquille porte-t-il du texte ? Jamais en partie (rien a masquer), jamais a
# la fin (la surface de fin s'en charge).
static func surface_de_menu(app_etat: int) -> bool:
	if App.tick_autorise(app_etat):
		return false
	return not surface_de_fin(app_etat)


# Nombre d'etats ou DEUX surfaces de texte sont rendues ensemble. La valeur attendue vaut
# exactement 0 — avant V4 elle valait 1 (l'etat FIN).
static func etats_a_double_surface() -> int:
	var n: int = 0
	for e in App.ETATS_VALIDES:
		if surface_de_fin(e) and surface_de_menu(e):
			n += 1
	return n


func _ready() -> void:
	get_window().size = Vector2i(Boot.largeur_fenetre(), Boot.hauteur_fenetre())
	_session = Boot.session_initiale()
	# REGLAGES PERSISTES (V3, cause racine P6) : ils sont lus ICI, au demarrage reel de la
	# scene, et jamais par la logique pure — settings.gd reste mesure sans FileAccess, sans
	# ConfigFile et sans user://, donc la valeur du premier lancement reste CONSTRUITE.
	_session = Sess.appliquer_reglages(_session, Options.charger())
	_construire_labels()
	# CHEMIN DE LECTURE AUDIO (V4, cause racine P1) : c'est ICI, et nulle part ailleurs,
	# que le flux synthetise rejoint un lecteur de plateforme. `_ready` garantit que le
	# noeud est dans l'arbre — condition sans laquelle le moteur refuse la lecture.
	Audio.brancher_lecteur(self)
	_rafraichir()
	Probe.emettre_session(_session)
	queue_redraw()


# Le lecteur audio est DEBRANCHE avec la scene qui l'a installe : il est tenu par une
# variable statique, donc rien d'autre ne le libererait. Mesure de ce poste le
# 2026-08-06 : sans cette ligne, la sortie du jeu signale « ObjectDB instances leaked ».
func _exit_tree() -> void:
	Audio.detacher_lecteur()


func _draw() -> void:
	if _session.get("partie", null) == null:
		return
	MazeView.dessiner(self, _session["partie"], Boot.largeur_fenetre(), Boot.hauteur_fenetre())
	# VOILE MODAL (V4, cause racine P2) : dessine APRES la carte et AVANT les enfants
	# Label — c'est l'ordre de rendu du canevas qui met le texte de fin au-dessus d'une
	# couche, au lieu de le melanger au labyrinthe.
	if surface_de_fin(int(_session["app"])):
		draw_rect(EndScreen.rect_modal(Boot.largeur_fenetre(), Boot.hauteur_fenetre()),
			Palette.FOND_MODAL)


func _process(delta: float) -> void:
	var r: Dictionary = avancer(_accum_ms, delta * 1000.0, P.PERIODE_TICK_MS, not tick_autorise(_session))
	_accum_ms = r["accumulateur"]
	if r["ticks"] != 1:
		return
	var sortie: Dictionary = Loop.step(_session["partie"], _demande, _dash_demande)
	_session["partie"] = sortie["etat"]
	var reglages: Dictionary = _session.get("reglages", {})
	Audio.jouer_evenements(sortie["evenements_sonores"], _session["partie"].ticks, reglages)
	# PISTE MUSICALE (V3, cause racine P3) : la note courante derive du temps de jeu, donc
	# du tick — jamais d'une horloge de plateforme. Meme moteur de synthese que les
	# bruitages, zero fichier son.
	Audio.jouer_musique(float(_session["partie"].ticks) * P.PERIODE_TICK_MS, reglages)
	_demande = Maze.AUCUNE
	_dash_demande = false
	if Progression.carte_videe(_session["partie"]):
		_session = Shell.enchainer_niveau(_session)
	# FIN DE PARTIE (V3, cause racine P5) : une partie terminee sur place — victoire ou
	# defaite — passe a l'ecran final, ou des suites sont OFFERTES. Sans ce passage, l'etat
	# restait PARTIE et aucune intention n'atteignait la coquille : impasse.
	_session = Shell.terminer_partie(_session)
	Probe.emettre_session(_session)
	_rafraichir()
	queue_redraw()


# Entree du moteur -> INTENTION -> canal public. L'adaptateur traduit, la logique decide.
func _input(event: InputEvent) -> void:
	var intention: int = Intents.Intention.AUCUNE
	var keycode: int = InputAdapter.keycode_de_event(event)
	if keycode != -1:
		intention = InputAdapter.intention_de_touche(keycode)
	else:
		var bouton: int = InputAdapter.bouton_de_event(event)
		if bouton != -1:
			intention = InputAdapter.intention_de_bouton(bouton)
		else:
			var contact: Vector2i = Touch.position_de_event(event)
			if contact.x >= 0:
				intention = Touch.intention_du_contact(
					contact, Boot.largeur_fenetre(), Boot.hauteur_fenetre())
	if intention == Intents.Intention.AUCUNE:
		return
	_appliquer(intention)


func _appliquer(intention: int) -> void:
	# En partie, les directions et le dash vont au tick ; tout le reste va a la coquille.
	if App.tick_autorise(int(_session["app"])) and intention != Intents.Intention.PAUSE:
		if Intents.est_direction(intention):
			_demande = InputAdapter.direction_de_intention(intention)
			return
		if intention == Intents.Intention.DASH:
			_dash_demande = true
			return
	var etat_avant: int = int(_session["app"])
	var reglages_avant: Dictionary = _session.get("reglages", {})
	var r: Dictionary = Shell.appliquer_intention(_session, intention)
	_session = r["session"]
	if r["ouverture_menu"]:
		Audio.jouer("son_pause", Sess.ticks_de_partie(_session), _session.get("reglages", {}))
	# PERSISTANCE (V3, cause racine P6) : un reglage modifie depuis l'ecran d'options est
	# ecrit sur le disque a l'instant ou il change. Ecrire a chaque intention ecrirait
	# aussi quand rien n'a bouge.
	if etat_avant == App.Etat.OPTIONS and _session.get("reglages", {}) != reglages_avant:
		Options.sauvegarder(_session["reglages"])
	if r["sortie"]:
		_quitter()
		return
	_accum_ms = 0.0
	Probe.emettre_session(_session)
	_rafraichir()
	queue_redraw()


# Sortie OBSERVABLE : dernier releve emis, boucle de tick arretee, processus termine.
func _quitter() -> void:
	Probe.emettre_session(_session)
	set_process(false)
	get_tree().quit(CODE_SORTIE)


func _construire_labels() -> void:
	var largeur: int = Boot.largeur_fenetre()
	var hauteur: int = Boot.hauteur_fenetre()
	_hud = Label.new()
	_hud.position = Vector2(8, 4)
	# Deux lignes depuis V4 : le bandeau de score, puis la PROGRESSION dans le catalogue.
	_hud.size = Vector2(largeur, 44)
	add_child(_hud)

	_banniere = Label.new()
	_banniere.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banniere.size = Vector2(largeur, 24)
	_banniere.position = Vector2(0, hauteur - 44)
	add_child(_banniere)

	# ECRAN DE FIN : sa geometrie vient de la MEME declaration que le voile modal, pour
	# que le texte ne puisse pas deborder de la couche qui le porte.
	var zone: Rect2 = EndScreen.rect_texte(largeur, hauteur)
	_fin = Label.new()
	_fin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fin.size = zone.size
	_fin.position = zone.position
	_fin.modulate = Palette.TEXTE
	add_child(_fin)

	_menu = Label.new()
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.size = Vector2(largeur, 240)
	_menu.position = Vector2(0, hauteur / 2 - 120)
	add_child(_menu)


func _rafraichir() -> void:
	var partie = _session.get("partie", null)
	var releve: Dictionary = {} if partie == null else Observable.projeter(partie)
	var etat_app: int = int(_session["app"])
	if partie == null:
		_hud.text = ""
		_banniere.text = ""
		_fin.text = ""
	else:
		# PROGRESSION (V4, cause racine P4) : carte courante / total du catalogue,
		# objectif chiffre, et ce que debloque la sortie. Le total est LU dans le
		# catalogue par la coquille et REMIS — l'affichage n'ouvre aucun fichier.
		_hud.text = (Hud.ligne(releve) + "    " + Presentation.texte_niveau(releve)
			+ "\n" + Hud.ligne_progression(releve, Shell.nb_niveaux()))
		_banniere.text = Banner.mention(releve) + "    " + Presentation.mention_dash(releve)
		_banniere.modulate = Banner.couleur(releve)
		# UNE SEULE SURFACE (V4, cause racine P2) : le recap n'est rendu qu'a l'etat FIN.
		_fin.text = EndScreen.recap(releve, int(_session.get("selection", 0))) if surface_de_fin(etat_app) else ""
	var contexte: Dictionary = {
		"selection": _session.get("selection", 0),
		"reglages": _session.get("reglages", {}),
		"releve": releve,
	}
	var ecran: Dictionary = ShellView.ecran(etat_app, contexte)
	if surface_de_menu(etat_app):
		_menu.text = String(ecran["titre"]) + "\n" + "\n".join(ecran["lignes"])
	else:
		_menu.text = ""
	_menu.modulate = ecran["couleur_texte"]
