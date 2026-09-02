# Point d'entrée de simulation headless pour grid_nav_probe.
# Lancer : godot --headless --path games/grid_nav_probe --script res://trial.gd --seed=<N>
# Émet : FORGE_TRIAL {"succeeded": bool, "ticks": number|null}
# Exit : 0 (toujours), ou 2 si argument manquant/invalide.
extends SceneTree

const GridNav = preload("res://core/grid_nav.gd")
const PREFIX := "FORGE_TRIAL "

func _initialize() -> void:
	var args := _parse_args()
	if not args.has("seed"):
		printerr("argument --seed=<N> manquant")
		quit(2)
		return

	var seed_str: String = args["seed"]
	if not seed_str.is_valid_int():
		printerr("--seed argument doit être un entier valide")
		quit(2)
		return

	var seed_value: int = int(seed_str)

	# Extraire max_ticks si fourni.
	var max_ticks := 200
	if args.has("max_ticks"):
		var max_ticks_str: String = args["max_ticks"]
		if max_ticks_str.is_valid_int():
			max_ticks = int(max_ticks_str)

	var result = run_simulation(seed_value, max_ticks)

	print(PREFIX + JSON.stringify(result))
	quit(0)

## Simule une session de navigation de labyrinthe seedée.
## Retourne {"succeeded": bool, "ticks": int|null}
func run_simulation(seed: int, max_ticks: int) -> Dictionary:
	# Générer un labyrinthe déterministe à partir du seed.
	var maze_width := 16
	var maze_height := 16
	var walls = _generate_maze_deterministic(seed, maze_width, maze_height)

	# Placer un agent et une cible.
	var agent_pos = Vector2i(1, 1)
	var target_pos = Vector2i(maze_width - 2, maze_height - 2)

	return run_simulation_with_walls(walls, agent_pos, target_pos, max_ticks)

## CORRECTIF (escalade Task 8fix) : boucle de simulation extraite de
## run_simulation() pour accepter un `walls` FOURNI en argument, au lieu de
## toujours générer le sien. Isolée pour être testable en isolation par
## tests/run_tests.gd — c'est le contrôle négatif : une cible entièrement
## murée doit produire succeeded=false, ce qui prouve que cette issue est
## ATTEIGNABLE (sans quoi "50/50 gagnés" ne serait pas une mesure).
## Fonction pure, static : ne modifie pas walls, aucun état partagé.
## Retourne {"succeeded": bool, "ticks": int|null}
static func run_simulation_with_walls(walls: Dictionary, agent_pos: Vector2i, target_pos: Vector2i, max_ticks: int) -> Dictionary:
	var ticks := 0
	var current_pos := agent_pos
	while ticks < max_ticks and current_pos != target_pos:
		var next_pos: Vector2i = GridNav.next_step(current_pos, target_pos, walls)
		if next_pos == current_pos:
			# next_step ne progresse plus (cible inatteignable depuis ici) :
			# échouer explicitement plutôt que consommer les ticks restants.
			break
		current_pos = next_pos
		ticks += 1

	var succeeded: bool = (current_pos == target_pos)
	return {"succeeded": succeeded, "ticks": (ticks if succeeded else null)}

## Génère un labyrinthe déterministe à partir du seed.
## Utilise un hash prédéfini au lieu de randi (interdit par R10).
##
## CORRECTIF (escalade Task 8) : l'ancienne version dégageait un corridor fixe en
## L (toute la ligne y=1 + toute la colonne x=width-2), qui est TOUJOURS le plus
## court chemin possible (longueur Manhattan-minimale entre (1,1) et
## (width-2,height-2)) quel que soit le seed -> ticks constant = 26 pour toute
## graine, mesure dégénérée. Un chemin creusé inconditionnel avait alors été
## REJETÉ pour ce même motif (borne Manhattan atteinte quoi qu'il arrive).
##
## RENVERSEMENT (escalade Task 8fix, défaut CRITIQUE) : ce même arbitrage a été
## rouvert côté solvability.gd, où le générateur interrogeait GridNav.path_length
## — la brique même qu'on teste — pour décider s'il fallait un chemin de
## secours. Deux fonctions du même BFS partagé se répondaient l'une à l'autre :
## l'oracle ne pouvait jamais détecter next_step cassé. Le correctif retenu là-bas
## (creuser INCONDITIONNELLEMENT, sans jamais consulter GridNav) est appliqué ici
## À L'IDENTIQUE, par cohérence de contrat ("aucun des deux générateurs ne doit
## appeler GridNav.path_length"). CONSÉQUENCE ASSUMÉE, PAS CACHÉE : la variance de
## ticks mesurée par trial.gd redevient dégénérée (le chemin creusé est de
## nouveau Manhattan-minimal, donc constant par construction) — c'est le prix du
## fait que le générateur ne demande plus RIEN à la brique. Distribution réelle
## à mesurer sur ≥15 graines (cf. task-8fix-report.md) pour recalibrer la bande
## de difficulté séparément ; ce fichier ne maquille pas le résultat.
func _generate_maze_deterministic(seed: int, width: int, height: int) -> Dictionary:
	var walls = {}

	# Hash déterministe linéaire : (seed * position + offset) % MOD.
	var mod := 65521  # nombre premier
	for y in range(height):
		for x in range(width):
			var pos_hash: int = ((seed * (x + y * width)) + x * 73 + y * 83) % mod
			# Probabilité de mur = pos_hash % 10 > 6, ~30% des cellules.
			if (pos_hash % 10) > 3:
				walls[Vector2i(x, y)] = true

	var start := Vector2i(1, 1)
	var target := Vector2i(width - 2, height - 2)
	walls.erase(start)
	walls.erase(target)

	# Inconditionnel : jamais de question posée à GridNav sur sa propre solvabilité.
	_carve_fallback_path(seed, width, height, start, target, walls)

	return walls

## Repli de secours : creuse un chemin monotone (n'avance que vers la cible)
## dépendant du seed, UNIQUEMENT appelé quand le labyrinthe issu du hachage
## seul est injouable pour cette graine. Garantit la solvabilité de cette
## instance ; ne prétend pas préserver la variance de ticks pour ce cas précis
## (assumé -- cf. commentaire de _generate_maze_deterministic). Mute `walls`
## en place (fonction de secours interne, pas la brique publique GridNav).
func _carve_fallback_path(seed: int, width: int, height: int, start: Vector2i, target: Vector2i, walls: Dictionary) -> void:
	var mod := 65521
	var cursor := start
	var step_index := 0
	var max_steps := width + height  # borne dure : un chemin monotone ne dépasse jamais width+height pas
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
