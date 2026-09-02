# v2_settings_mode_default_normal.test.gd — ligne settings.mode_default_normal, capacite F82.
# Au PREMIER LANCEMENT le mode vaut exactement mode normal, sans reglage prealable ni
# etat persistant herite : la valeur initiale est CONSTRUITE, jamais lue sur le disque.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	var initial: Dictionary = Reglages.initial()
	h.eq(initial["mode"], Reglages.Mode.NORMAL, "settings.defaut: le mode initial vaut NORMAL")
	h.eq(Reglages.MODE_PAR_DEFAUT, Reglages.Mode.NORMAL, "settings.defaut: le defaut declare vaut NORMAL")
	h.eq(initial["dash_actif"], Reglages.DASH_ACTIF_PAR_DEFAUT, "settings.defaut: dash au defaut declare")
	# V3 : trois reglages ajoutes (volume musique, volume effets, coupe-son). Ils sont
	# CONSTRUITS comme les deux premiers — la persistance vit dans l'adaptateur, et les
	# trois assertions ci-dessous continuent de le prouver sur ce fichier.
	h.eq(initial.size(), 5, "settings.defaut: cinq reglages declares")

	# CONSTRUITE, jamais lue : le module ne touche a aucun fichier.
	var f := FileAccess.open("res://05_SYSTEMS/settings/settings.gd", FileAccess.READ)
	h.ok(f != null, "settings.defaut: le module est lisible")
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("FileAccess"), false, "settings.defaut: aucune lecture de fichier")
	h.eq(texte.contains("ConfigFile"), false, "settings.defaut: aucun fichier de configuration")
	h.eq(texte.contains("user://"), false, "settings.defaut: aucun etat persistant")

	# La session d'amorcage et la premiere partie exposent le mode NORMAL.
	var sess: Dictionary = Shell.session_initiale()
	h.eq(sess["reglages"]["mode"], Reglages.Mode.NORMAL, "settings.defaut: la session amorce en NORMAL")
	var jeu = State.initial(Maze, 1)
	h.eq(jeu.mode, Reglages.Mode.NORMAL, "settings.defaut: la partie neuve amorce en NORMAL")
	h.eq(Observable.projeter(jeu)["mode_jeu"], "NORMAL", "settings.defaut: le releve expose NORMAL")

	# Deux amorcages successifs donnent la MEME valeur : rien n'est herite entre les deux.
	h.eq(Shell.session_initiale()["reglages"], sess["reglages"], "settings.defaut: aucun heritage entre amorcages")
	h.eq(Sess.initiale()["reglages"]["mode"], Reglages.Mode.NORMAL, "settings.defaut: session nue en NORMAL")
