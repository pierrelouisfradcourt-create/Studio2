# Oracle de solvabilite pour grid_nav_probe — decline R9 ("un bot doit reellement
# gagner") pour un projet Godot : un bot deterministe qui utilise
# GridNav.next_step pour atteindre la sortie d'un labyrinthe seede, sous
# max_ticks. succeeded=true UNIQUEMENT si la sortie est reellement atteinte
# (jamais suppose : boucle explicite pas-a-pas, comme un vrai joueur).
#
# Difference de role avec trial.gd (meme labyrinthe, meme mecanique de jeu) :
#   - trial.gd        mesure une BANDE DE DIFFICULTE (combien de ticks pour une
#                      seule graine) ; consomme par godot_trial.mjs / role_sim.mjs.
#   - solvability.gd   prouve la GAGNABILITE (oui/non) sur N graines ; consomme
#                      par scripts/forge/solvability_godot.mjs (oracle R9).
#
# Partage de code (arbitrage) : la generation de labyrinthe et la boucle de
# simulation de trial.gd sont des methodes PRIVEES (_generate_maze_deterministic,
# _carve_fallback_path) d'un script qui `extends SceneTree` — donc pas une API
# reutilisable proprement, et cette tache n'a pas mandat pour toucher trial.gd
# ni pour creer un nouveau module core/ partage (hors perimetre "Files" de la
# tache 10). Le code ci-dessous est donc duplique intentionnellement : legere
# redondance assumee plutot qu'un couplage fragile (ex. instancier
# `preload("res://trial.gd").new()` pour emprunter une methode privee d'un
# script qui n'est normalement JAMAIS instancie hors du bootstrap moteur, un
# script `extends SceneTree` etant cense etre LE main loop, pas un objet
# ordinaire qu'on cree a la volee).
#
# MISE A JOUR (escalade Task 8fix) : le paragraphe ci-dessus decrit le mandat
# ORIGINEL (tache 10, generation de labyrinthe seule). La tache 8fix a depuis
# corrige le defaut tautologique (path_length interrogeant la brique testee)
# ICI ET dans trial.gd::_generate_maze_deterministic, par coherence de contrat
# ("aucun des deux generateurs n'appelle GridNav.path_length"). La duplication
# de code documentee ci-dessus reste vraie et assumee ; seule la regle
# "ne pas toucher trial.gd" a ete explicitement levee par le contrat 8fix.
#
# Purete (contrat de la tache) : aucun alea non seede, aucune dependance a
# l'horloge. randi/randf/randomize/Time.* sont INTERDITS ici — seul le hash
# deterministe (seed, x, y) pilote la generation, a l'identique de trial.gd :
# meme graine + meme max_ticks => meme resultat, toujours.
#
# Lancer : godot --headless --path games/grid_nav_probe --script res://solvability.gd -- --seed=<N> --max_ticks=<N>
# Emet   : FORGE_TRIAL {"succeeded": bool, "ticks": number|null}
# Exit   : 0 (toujours), ou 2 si argument manquant/invalide.
extends SceneTree

const GridNav = preload("res://core/grid_nav.gd")
const PREFIX := "FORGE_TRIAL "
const MAZE_WIDTH := 16
const MAZE_HEIGHT := 16
const DEFAULT_MAX_TICKS := 200

func _initialize() -> void:
	var args := _parse_args()
	if not args.has("seed"):
		printerr("argument --seed=<N> manquant")
		quit(2)
		return

	var seed_str: String = args["seed"]
	if not seed_str.is_valid_int():
		printerr("--seed argument doit etre un entier valide")
		quit(2)
		return

	var seed_value: int = int(seed_str)

	# Extraire max_ticks si fourni.
	var max_ticks := DEFAULT_MAX_TICKS
	if args.has("max_ticks"):
		var max_ticks_str: String = args["max_ticks"]
		if max_ticks_str.is_valid_int():
			max_ticks = int(max_ticks_str)

	var result := solve(seed_value, max_ticks)

	print(PREFIX + JSON.stringify(result))
	quit(0)

## Fait jouer le bot GridNav.next_step sur un labyrinthe seede, pas a pas,
## jusqu'a la sortie ou jusqu'a max_ticks. Ne DEDUIT jamais le succes : ne
## renvoie succeeded=true que si la position finale EST reellement la cible.
## Retourne {"succeeded": bool, "ticks": int|null}.
func solve(seed: int, max_ticks: int) -> Dictionary:
	var walls := _generate_maze_deterministic(seed, MAZE_WIDTH, MAZE_HEIGHT)
	var agent_pos := Vector2i(1, 1)
	var target_pos := Vector2i(MAZE_WIDTH - 2, MAZE_HEIGHT - 2)

	var ticks := 0
	var current_pos := agent_pos
	while ticks < max_ticks and current_pos != target_pos:
		var next_pos: Vector2i = GridNav.next_step(current_pos, target_pos, walls)
		if next_pos == current_pos:
			# next_step ne progresse plus (cible inatteignable depuis ici) :
			# echouer explicitement plutot que consommer les ticks restants
			# a ne rien faire.
			break
		current_pos = next_pos
		ticks += 1

	var succeeded: bool = (current_pos == target_pos)
	return {"succeeded": succeeded, "ticks": (ticks if succeeded else null)}

## Genere un labyrinthe deterministe a partir du seed. Duplique de
## trial.gd::_generate_maze_deterministic (cf. arbitrage en en-tete) : hash
## lineaire (seed, x, y), ~30% de murs.
##
## CORRECTIF (escalade Task 8fix, defaut CRITIQUE) : l'ancienne version
## demandait a GridNav.path_length — la brique meme qu'on teste — si un chemin
## de secours etait necessaire. Consequence : succeeded ne pouvait etre faux
## que si next_step contredisait path_length, deux fonctions du MEME BFS
## partage. "50/50 gagnes" ne prouvait donc rien, c'etait vrai par
## construction. Correctif retenu : le chemin de secours est desormais creuse
## INCONDITIONNELLEMENT, deterministe et depend de la graine, SANS jamais
## consulter GridNav. Le chemin existe alors parce que CE generateur l'a
## trace — fait independant de tout ce que la brique pense. Si next_step est
## casse, le bot n'atteindra pas la cible malgre ce chemin garanti =>
## succeeded=false => l'oracle detecte enfin une brique defaillante (preuve
## par le controle negatif dans tests/run_tests.gd : cible entierement muree
## => succeeded=false, atteignable).
func _generate_maze_deterministic(seed: int, width: int, height: int) -> Dictionary:
	var walls := {}

	var mod := 65521  # nombre premier
	for y in range(height):
		for x in range(width):
			var pos_hash: int = ((seed * (x + y * width)) + x * 73 + y * 83) % mod
			if (pos_hash % 10) > 3:
				walls[Vector2i(x, y)] = true

	var start := Vector2i(1, 1)
	var target := Vector2i(width - 2, height - 2)
	walls.erase(start)
	walls.erase(target)

	# Inconditionnel : jamais de question posee a GridNav sur sa propre solvabilite.
	_carve_fallback_path(seed, width, height, start, target, walls)

	return walls

## Repli de secours, duplique de trial.gd::_carve_fallback_path : creuse un
## chemin monotone (n'avance que vers la cible) seede, UNIQUEMENT quand le
## labyrinthe issu du hash seul est injouable pour cette graine precise. Mute
## walls en place (fonction de secours interne, pas la brique publique GridNav).
func _carve_fallback_path(seed: int, width: int, height: int, start: Vector2i, target: Vector2i, walls: Dictionary) -> void:
	var mod := 65521
	var cursor := start
	var step_index := 0
	var max_steps := width + height  # borne dure : un chemin monotone ne depasse jamais width+height pas
	while cursor != target and step_index < max_steps:
		var dx := target.x - cursor.x
		var dy := target.y - cursor.y
		var can_h := dx != 0
		var can_v := dy != 0
		var choose_horizontal: bool
		if can_h and can_v:
			var h: int = ((seed * 97) + step_index * 131 + cursor.x * 17 + cursor.y * 19) % mod
			choose_horizontal = (h % 2) == 0
		elif can_h:
			choose_horizontal = true
		else:
			choose_horizontal = false
		if choose_horizontal:
			cursor.x += (1 if dx > 0 else -1)
		else:
			cursor.y += (1 if dy > 0 else -1)
		walls.erase(cursor)
		step_index += 1

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var parts := a.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
