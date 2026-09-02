# runtime_boot_window.gd — ligne runtime.boot_window, capacite F42.
# Lancement RESEAU COUPE : le jeu s'ouvre et une partie se joue, sans charger AUCUN
# fichier d'image, de police ni de son importe.
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const MazeView = preload("res://06_RUNTIME/adapters/presentation/maze_view.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Inventory = preload("res://06_RUNTIME/adapters/proof_harness/asset_inventory.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# L'etat initial est ATTEINT sans aucun geste : zero appui, zero ecran intercale.
	var etat = Boot.etat_initial()
	h.eq(etat.ticks, 0, "runtime.boot: etat initial au tick 0")
	h.eq(etat.statut, State.Statut.EN_COURS, "runtime.boot: la partie est immediatement jouable")
	h.eq(etat.pac, Maze.DEPART_PACMAN, "runtime.boot: Pac-Man est a sa case de depart")
	h.eq(etat.total_pose, 244, "runtime.boot: les 244 collectibles sont poses")

	# La graine d'amorcage est DECLAREE : le lancement au clavier est reproductible.
	var second = Boot.etat_initial()
	h.eq(etat.egal_profond(second), true, "runtime.boot: deux amorcages donnent le meme etat")

	# La FENETRE contient la grille ENTIERE, sans defilement.
	h.eq(Boot.largeur_fenetre(), MazeView.largeur_pixels(Maze), "runtime.boot: largeur de fenetre declaree")
	h.eq(Boot.hauteur_fenetre(), MazeView.hauteur_pixels(Maze), "runtime.boot: hauteur de fenetre declaree")
	h.eq(Boot.fenetre_contient_grille(Boot.largeur_fenetre(), Boot.hauteur_fenetre()), true,
		"runtime.boot: la fenetre declaree contient la grille entiere")
	h.eq(Boot.fenetre_contient_grille(MazeView.largeur_pixels(Maze) - 1, MazeView.hauteur_pixels(Maze)), false,
		"runtime.boot: une fenetre trop etroite est refusee")
	h.eq(MazeView.largeur_pixels(Maze), Maze.LARGEUR * MazeView.COTE_CASE, "runtime.boot: largeur = 28 cases")
	h.eq(MazeView.hauteur_pixels(Maze), Maze.HAUTEUR * MazeView.COTE_CASE, "runtime.boot: hauteur = 36 cases")

	# La scene principale est declaree dans project.godot — c'est le critere MECANIQUE
	# qui distingue un JEU d'un module de bibliotheque pour l'oracle maitre.
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	h.ok(f != null, "runtime.boot: project.godot est lisible")
	var contenu: String = f.get_as_text() if f != null else ""
	h.ok(contenu.contains("run/main_scene=\"res://main.tscn\""), "runtime.boot: main_scene declaree")
	h.ok(contenu.contains("config_version=5"), "runtime.boot: config_version 5")
	h.ok(FileAccess.file_exists("res://main.tscn"), "runtime.boot: main.tscn existe")

	# RESEAU COUPE, ZERO ASSET : l'inventaire du projet ne contient aucun asset importe.
	var mesure: Dictionary = Inventory.mesurer()
	h.eq(mesure["assets_importes"], 0, "runtime.boot: aucun fichier d'image, de police ni de son")
	h.gt(mesure["fichiers"], 0, "runtime.boot: l'inventaire a reellement parcouru le projet")

	# UNE PARTIE SE JOUE reellement depuis cet amorcage.
	var jeu = Boot.etat_initial()
	for _t in range(60):
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
	h.eq(jeu.ticks, 60, "runtime.boot: la partie a joue 60 ticks depuis l'amorcage")
	h.gt(jeu.consommees, 0, "runtime.boot: des collectibles ont ete consommes")
	h.eq(jeu.statut, State.Statut.EN_COURS, "runtime.boot: la partie tourne toujours")
